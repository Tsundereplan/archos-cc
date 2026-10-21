--[[
    ArchOS-CC BIOS
    ===============
    The BIOS is the layer between the raw hardware (CraftOS) and the
    bootloader. It is responsible for:

      * Hardware detection (peripherals, drives, monitors, modems)
      * BIOS settings (persisted in /etc/bios.conf)
      * Boot device selection
      * Boot menu (press F2 during BIOS post)
      * POST (Power-On Self Test) diagnostics

    The BIOS runs BEFORE the bootloader hands off to a kernel. It writes
    a hardware report to /var/log/boot.log and exposes a hw table to the
    bootloader via _G.BIOS.
]]

local BIOS = {}

-- Defaults
BIOS.version = "1.0.0"
BIOS.config = {
    bootDelay       = 2,        -- seconds to show POST screen
    defaultBoot     = "archos", -- default boot entry
    enableSplash    = true,
    enableBootMenu  = true,     -- show boot menu if multiple OSes
    enablePnP       = true,     -- Plug and Play auto-detection
    enableNetwork   = true,     -- auto-init network on boot
    enableDebugLog  = true,     -- write to /var/log/boot.log
    enableGUI       = true,     -- can use paintutils for splash
    fontSize        = "normal", -- normal/small for monitor display
    colorscheme     = "arch",   -- arch/forest/ocean/sunset/dark
}

BIOS.hw = {
    peripherals = {},  -- side -> type
    drives      = {},  -- side -> mount info
    monitors    = {},  -- side -> terminal redirect
    modems      = {},  -- side -> {wired=true, wireless=true}
    speakers    = {},
    printers    = {},
    network     = { -- populated during PnP init
        online = false,
        ip = nil,
        channel = nil
    },
    advanced     = term.isColor(),
    computerType = os.getComputerLabel() or "computer",
    computerID   = os.getComputerID(),
    isTurtle     = turtle ~= nil,
    isPocket     = pocket ~= nil,
}

-- Logging
local function log(msg)
    if not BIOS.config.enableDebugLog then return end
    if not fs.exists("/var/log") then fs.makeDir("/var/log") end
    local f = fs.open("/var/log/boot.log", "a")
    if f then
        f.write("[" .. os.date("%H:%M:%S") .. "] [BIOS] " .. tostring(msg) .. "\n")
        f.close()
    end
end

BIOS.log = log

-- Configuration persistence
local CONFIG_PATH = "/etc/bios.conf"

function BIOS.loadConfig()
    if not fs.exists(CONFIG_PATH) then
        BIOS.saveConfig(BIOS.config)
        return BIOS.config
    end
    local f = fs.open(CONFIG_PATH, "r")
    if not f then return BIOS.config end
    local content = f.readAll()
    f.close()
    -- Serialize text format: key=value
    for line in content:gmatch("[^\r\n]+") do
        local key, val = line:match("^%s*([%w_]+)%s*=%s*(.*)$")
        if key and val then
            val = val:gsub("^%s+", ""):gsub("%s+$", "")
            if val == "true" then val = true
            elseif val == "false" then val = false
            elseif tonumber(val) then val = tonumber(val)
            end
            BIOS.config[key] = val
        end
    end
    return BIOS.config
end

function BIOS.saveConfig(cfg)
    if not fs.exists("/etc") then fs.makeDir("/etc") end
    local f = fs.open(CONFIG_PATH, "w")
    if not f then return false end
    for k, v in pairs(cfg) do
        local val
        if type(v) == "string" then val = v
        elseif type(v) == "number" then val = tostring(v)
        elseif type(v) == "boolean" then val = v and "true" or "false"
        else val = tostring(v) end
        f.write(k .. "=" .. val .. "\n")
    end
    f.close()
    return true
end

-- POST: Power-On Self Test
function BIOS.post()
    log("=== BIOS POST start ===")
    log("BIOS version: " .. BIOS.version)
    log("Computer ID: " .. tostring(BIOS.hw.computerID))
    log("Computer label: " .. tostring(BIOS.hw.computerType))
    log("Advanced (color): " .. tostring(BIOS.hw.advanced))

    -- Check critical files
    local critical = {
        "/startup.lua",
        "/bootloader/bootloader.lua",
        "/kernel/init.lua",
        "/bin/sh.lua",
        "/lib/fs.lua",
        "/lib/users.lua",
    }
    local missing = {}
    for _, path in ipairs(critical) do
        if not fs.exists(path) then
            missing[#missing+1] = path
        end
    end
    if #missing > 0 then
        log("POST WARNING: missing critical files:")
        for _, p in ipairs(missing) do log("  - " .. p) end
    end

    -- Check disk space
    local free = fs.getFreeSpace("/")
    log("Free disk space: " .. tostring(free) .. " bytes")
    if free and free < 10000 then
        log("POST WARNING: low disk space")
    end

    -- Detect peripherals
    BIOS.scanPeripherals()

    -- Init PnP if enabled
    if BIOS.config.enablePnP then
        BIOS.initPnP()
    end

    log("=== BIOS POST end ===")
    return #missing == 0
end

-- Count entries in a table (used by scanPeripherals).
-- Defined BEFORE scanPeripherals to avoid forward-reference issues.
local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- Peripheral scanning
function BIOS.scanPeripherals()
    BIOS.hw.peripherals = {}
    BIOS.hw.drives      = {}
    BIOS.hw.monitors    = {}
    BIOS.hw.modems      = {}
    BIOS.hw.speakers    = {}
    BIOS.hw.printers    = {}

    local sides = {"top", "bottom", "left", "right", "front", "back"}
    for _, side in ipairs(sides) do
        if peripheral.isPresent(side) then
            local ptype = peripheral.getType(side)
            BIOS.hw.peripherals[side] = ptype
            log("Peripheral: " .. side .. " = " .. ptype)

            if ptype == "drive" then
                -- Wrap the drive peripheral so we can call its methods
                -- directly. peripheral.call(side, "hasDisk") works in
                -- newer CC:T versions, but wrap+call is more universal.
                local drive = peripheral.wrap(side)
                local hasDisk = false
                local label = nil
                local id = nil
                if drive then
                    -- Use pcall in case the method doesn't exist
                    local ok1, res1 = pcall(function() return drive.hasDisk() end)
                    if ok1 then hasDisk = res1 == true end
                    if hasDisk then
                        local ok2, res2 = pcall(function() return drive.getDiskLabel() end)
                        if ok2 then label = res2 end
                        local ok3, res3 = pcall(function() return drive.getDiskID() end)
                        if ok3 then id = res3 end
                    end
                end
                BIOS.hw.drives[side] = { side=side, hasDisk=hasDisk, label=label, id=id, wrap=drive }
            elseif ptype == "monitor" then
                BIOS.hw.monitors[side] = peripheral.wrap(side)
            elseif ptype == "modem" then
                local m = peripheral.wrap(side)
                if m then
                    local wired = m.isWireless and m.isWireless() or false
                    -- Note: isWireless returns true for wireless modems
                    table.insert(BIOS.hw.modems, {
                        side = side,
                        wrap = m,
                        wireless = wired,
                        channels = {}
                    })
                end
            elseif ptype == "speaker" then
                table.insert(BIOS.hw.speakers, peripheral.wrap(side))
            elseif ptype == "printer" then
                table.insert(BIOS.hw.printers, peripheral.wrap(side))
            end
        end
    end

    log("Peripherals: " .. count(BIOS.hw.peripherals))
    log("Drives: " .. count(BIOS.hw.drives))
    log("Monitors: " .. count(BIOS.hw.monitors))
    log("Modems: " .. #BIOS.hw.modems)
end

-- (count() is now defined as `local` at the top of this section)

-- Plug and Play initialization
function BIOS.initPnP()
    log("Initializing Plug and Play ...")
    -- Try to load PnP driver
    if fs.exists("/lib/drivers/pnp.lua") then
        local ok, pnp = pcall(dofile, "/lib/drivers/pnp.lua")
        if ok and type(pnp) == "table" and pnp.init then
            pnp.init(BIOS.hw)
            BIOS.pnp = pnp
            log("PnP driver initialized")
        else
            log("PnP driver load failed: " .. tostring(pnp))
        end
    else
        log("PnP driver not found (skipping)")
    end

    -- Auto-mount any disks present
    for side, info in pairs(BIOS.hw.drives) do
        if info.hasDisk then
            log("Auto-mounting disk at " .. side)
            local mountPoint = "/mnt/disk" .. tostring(info.id or side)
            if not fs.exists(mountPoint) then
                fs.makeDir(mountPoint)
            end
            -- Note: CC:Tweaked auto-mounts disks to /disk, /disk2 etc.
            -- We just track them.
        end
    end

    -- Auto-init network
    if BIOS.config.enableNetwork and #BIOS.hw.modems > 0 then
        log("Initializing network ...")
        local m = BIOS.hw.modems[1].wrap
        if m and m.open then
            -- Open default channel for rednet
            pcall(function()
                m.open(65535)  -- broadcast
                m.open(1)      -- system channel
            end)
            BIOS.hw.network.online = true
            BIOS.hw.network.channel = 1
            log("Network initialized on " .. BIOS.hw.modems[1].side)
        end
    end
end

-- POST screen display
function BIOS.showPost()
    if not BIOS.config.enableSplash then return end

    local w, h = term.getSize()
    -- Defensive: use setBackgroundColour (British) if present, else
    -- setBackgroundColor (American). Always wrap in pcall because some
    -- CC:T versions don't implement every alias.
    pcall(function() pcall(function() term.setBackgroundColour(colors.black) end); pcall(function() term.setBackgroundColor(colors.black) end) end)
    pcall(function() term.setBackgroundColor(colors.black) end)
    term.clear()
    term.setCursorPos(1, 1)

    -- Defensive color setter
    local function setFG(c)
        if not c then return end
        if not BIOS.hw.advanced then return end
        pcall(function() pcall(function() term.setTextColour(c) end); pcall(function() term.setTextColor(c) end) end)
        pcall(function() term.setTextColor(c) end)
    end

    -- Title
    setFG(colors.lightBlue)
    print("")
    print("    ArchOS-CC BIOS v" .. BIOS.version)
    print("    =======================")
    print("")

    setFG(colors.gray)
    print("  Computer : " .. tostring(BIOS.hw.computerType))
    print("  ID       : " .. tostring(BIOS.hw.computerID))
    print("  Advanced : " .. tostring(BIOS.hw.advanced))
    print("  Turtle   : " .. tostring(BIOS.hw.isTurtle))
    print("  Pocket   : " .. tostring(BIOS.hw.isPocket))
    print("")

    -- Memory/disk info
    print("  Free disk: " .. tostring(fs.getFreeSpace("/")) .. " bytes")
    print("")

    -- Peripherals detected
    setFG(colors.cyan)
    print("  Hardware detected:")
    setFG(colors.white)
    local count = 0
    for side, ptype in pairs(BIOS.hw.peripherals) do
        print("    " .. side .. " : " .. ptype)
        count = count + 1
    end
    if count == 0 then print("    (none)") end
    print("")

    -- Boot info
    if BIOS.hw.advanced then pcall(function() pcall(function() term.setTextColour(colors.yellow) end); pcall(function() term.setTextColor(colors.yellow) end) end); pcall(function() term.setTextColor(colors.yellow) end) end
    print("  Press F12 for Boot Menu  (or wait to auto-boot)")
    print("  Booting in " .. BIOS.config.bootDelay .. "s ...")

    -- Wait, watching for F12 (boot menu).
    -- Note: F2 (BIOS Setup) was removed because it doesn't work reliably
    -- in CC:Tweaked. F12 works fine.
    local timer = os.startTimer(BIOS.config.bootDelay)
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "timer" and ev[2] == timer then
            break
        elseif ev[1] == "key" then
            if ev[2] == keys.f12 then
                local choice = BIOS.bootMenu()
                if choice then return "boot", choice end
            end
        end
    end
end

-- BIOS Setup (interactive configuration)
function BIOS.setup()
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        if BIOS.hw.advanced then pcall(function() pcall(function() term.setTextColour(colors.lightBlue) end); pcall(function() term.setTextColor(colors.lightBlue) end) end); pcall(function() term.setTextColor(colors.lightBlue) end) end
        print("==========================================")
        print("       ArchOS-CC BIOS Setup")
        print("==========================================")
        print("")
        if BIOS.hw.advanced then pcall(function() pcall(function() term.setTextColour(colors.white) end); pcall(function() term.setTextColor(colors.white) end) end); pcall(function() term.setTextColor(colors.white) end) end

        local items = {
            {"1", "Boot delay        = " .. BIOS.config.bootDelay .. "s"},
            {"2", "Default boot      = " .. tostring(BIOS.config.defaultBoot)},
            {"3", "Splash screen     = " .. tostring(BIOS.config.enableSplash)},
            {"4", "Boot menu         = " .. tostring(BIOS.config.enableBootMenu)},
            {"5", "Plug and Play     = " .. tostring(BIOS.config.enablePnP)},
            {"6", "Network init      = " .. tostring(BIOS.config.enableNetwork)},
            {"7", "Debug log         = " .. tostring(BIOS.config.enableDebugLog)},
            {"8", "Color scheme      = " .. tostring(BIOS.config.colorscheme)},
            {"9", "Re-scan peripherals"},
            {"s", "Save & Exit"},
            {"q", "Exit without saving"},
        }
        for _, item in ipairs(items) do
            print("  [" .. item[1] .. "] " .. item[2])
        end
        print("")
        term.write("  Choice: ")
        local c = read()
        if c == "1" then
            term.write("  New delay (1-30): ")
            local n = tonumber(read())
            if n and n >= 1 and n <= 30 then BIOS.config.bootDelay = n end
        elseif c == "2" then
            term.write("  Default boot entry: ")
            local v = read()
            if v and v ~= "" then BIOS.config.defaultBoot = v end
        elseif c == "3" then BIOS.config.enableSplash = not BIOS.config.enableSplash
        elseif c == "4" then BIOS.config.enableBootMenu = not BIOS.config.enableBootMenu
        elseif c == "5" then BIOS.config.enablePnP = not BIOS.config.enablePnP
        elseif c == "6" then BIOS.config.enableNetwork = not BIOS.config.enableNetwork
        elseif c == "7" then BIOS.config.enableDebugLog = not BIOS.config.enableDebugLog
        elseif c == "8" then
            term.write("  Color scheme (arch/forest/ocean/sunset/dark): ")
            local v = read()
            if v and v ~= "" then BIOS.config.colorscheme = v end
        elseif c == "9" then
            BIOS.scanPeripherals()
            term.write("  Rescan complete. Press Enter ..."); read()
        elseif c == "s" then
            BIOS.saveConfig(BIOS.config)
            term.write("  Saved. Press Enter to continue boot ..."); read()
            return
        elseif c == "q" then
            return
        end
    end
end

-- Boot menu — list installed OSes
function BIOS.bootMenu()
    term.clear()
    term.setCursorPos(1, 1)
    if BIOS.hw.advanced then pcall(function() pcall(function() term.setTextColour(colors.lightBlue) end); pcall(function() term.setTextColor(colors.lightBlue) end) end); pcall(function() term.setTextColor(colors.lightBlue) end) end
    print("==========================================")
    print("       ArchOS-CC Boot Menu")
    print("==========================================")
    print("")

    -- Scan /bootloader/entries/ for installed OSes
    local entries = {}
    if fs.exists("/bootloader/entries") and fs.isDir("/bootloader/entries") then
        for _, name in ipairs(fs.list("/bootloader/entries")) do
            if name:sub(-4) == ".lua" then
                table.insert(entries, name:sub(1, -5))
            end
        end
    end
    -- Always include archos
    local found = false
    for _, e in ipairs(entries) do if e == "archos" then found = true break end end
    if not found then table.insert(entries, "archos") end

    if BIOS.hw.advanced then pcall(function() pcall(function() term.setTextColour(colors.white) end); pcall(function() term.setTextColor(colors.white) end) end); pcall(function() term.setTextColor(colors.white) end) end
    for i, name in ipairs(entries) do
        print("  " .. i .. ". " .. name)
    end
    print("")
    term.write("  Select (1-" .. #entries .. "): ")
    local c = tonumber(read())
    if c and c >= 1 and c <= #entries then
        return entries[c]
    end
    return nil
end

-- Main BIOS entry point
function BIOS.run()
    BIOS.loadConfig()
    local ok = BIOS.post()
    if not ok then
        if BIOS.hw.advanced then pcall(function() pcall(function() term.setTextColour(colors.red) end); pcall(function() term.setTextColor(colors.red) end) end); pcall(function() term.setTextColor(colors.red) end) end
        print("[BIOS] POST detected missing files. Boot may fail.")
        os.sleep(1)
    end
    local action = BIOS.showPost()
    -- Expose state to bootloader via _G
    _G.BIOS = BIOS
    return action or "boot"
end

-- Expose BIOS table globally even before run() (for bootloader to query)
_G.BIOS = BIOS

return BIOS
