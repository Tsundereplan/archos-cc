--[[
    ArchOS-CC Open Bootloader
    =========================
    An OS-agnostic bootloader for ComputerCraft: Tweaked computers.

    Architecture:
      /bootloader/
        bootloader.lua           <- this file
        entries/                 <- one .lua file per installed OS
          archos.lua             <- ArchOS-CC entry
          craftos.lua            <- vanilla CraftOS entry (optional)
          custom.lua             <- any other OS (user-defined)
        default                  <- file containing default entry name

    Each entry file must `return { name=..., kernel=..., init=..., args=... }`.
    The bootloader loads it, then runs the specified kernel/init file.

    Behavior:
      1. Load /bios/bios.lua (the BIOS layer)
      2. BIOS runs POST and shows splash
      3. If user pressed F12 in BIOS or if multiple entries exist,
         show boot menu
      4. Otherwise boot the default entry
      5. The kernel file is loaded with dofile() and called with the
         entry's args + BIOS state.
]]

local Bootloader = {}

local BOOT_ENTRIES_DIR = "/bootloader/entries"
local BOOT_DEFAULT_FILE = "/bootloader/default"

-- Logging
local function log(msg)
    if _G.BIOS and _G.BIOS.log then
        _G.BIOS.log("[BOOT] " .. msg)
    end
end

-- Detect available boot entries
function Bootloader.listEntries()
    local entries = {}
    if fs.exists(BOOT_ENTRIES_DIR) and fs.isDir(BOOT_ENTRIES_DIR) then
        for _, name in ipairs(fs.list(BOOT_ENTRIES_DIR)) do
            if name:sub(-4) == ".lua" then
                local entryName = name:sub(1, -5)
                local path = BOOT_ENTRIES_DIR .. "/" .. name
                local ok, entry = pcall(dofile, path)
                if ok and type(entry) == "table" and entry.kernel then
                    entries[entryName] = entry
                else
                    log("Invalid entry: " .. name .. " - " .. tostring(entry))
                end
            end
        end
    end

    -- Always have a built-in archos fallback if missing
    if not entries["archos"] then
        entries["archos"] = {
            name    = "ArchOS-CC",
            kernel  = "/kernel/init.lua",
            init    = "/sbin/init.lua",
            description = "Arch Linux style OS for CC:Tweaked"
        }
    end
    -- Always have a built-in craftos fallback if missing
    if not entries["craftos"] then
        entries["craftos"] = {
            name        = "CraftOS 1.9",
            kernel      = "/kernel/craftos-shim.lua",
            description = "Boot into the standard CraftOS 1.9 shell (no ArchOS)",
        }
    end
    return entries
end

function Bootloader.getDefault()
    if fs.exists(BOOT_DEFAULT_FILE) then
        local f = fs.open(BOOT_DEFAULT_FILE, "r")
        if f then
            local name = f.readAll()
            f.close()
            name = name:gsub("^%s+", ""):gsub("%s+$", "")
            if name ~= "" then return name end
        end
    end
    -- Fallback to BIOS default if set
    if _G.BIOS and _G.BIOS.config and _G.BIOS.config.defaultBoot then
        return _G.BIOS.config.defaultBoot
    end
    return "archos"
end

-- GRUB-like interactive boot menu.
-- User can navigate with up/down arrows, Enter to boot, or type a number.
-- Falls back to numbered prompt if arrow keys aren't available.
function Bootloader.showMenu(entries)
    local entriesList = {}
    for name, _ in pairs(entries) do
        table.insert(entriesList, name)
    end
    table.sort(entriesList)

    local selected = 1
    -- Find default entry to pre-select
    local def = Bootloader.getDefault()
    for i, name in ipairs(entriesList) do
        if name == def then selected = i; break end
    end

    local function render()
        local w, h = term.getSize()
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)
        -- GRUB-style header
        if term.isColor() then
            term.setTextColor(colors.cyan)
            term.setBackgroundColor(colors.blue)
        end
        -- Top bar
        term.write(" " .. string.rep(" ", w - 2) .. " ")
        term.setCursorPos(1, 1)
        term.write(" GNU GRUB  -  ArchOS-CC Bootloader")
        term.setCursorPos(1, 2)
        term.write(string.rep("=", w))
        term.setBackgroundColor(colors.black)

        if term.isColor() then term.setTextColor(colors.lightGray) end
        term.setCursorPos(1, 3)
        print(" Select an OS to boot:")
        print("")

        -- Menu items
        for i, name in ipairs(entriesList) do
            local entry = entries[name]
            local desc = entry.description or ""
            if i == selected then
                if term.isColor() then
                    term.setBackgroundColor(colors.white)
                    term.setTextColor(colors.black)
                end
            else
                if term.isColor() then
                    term.setBackgroundColor(colors.black)
                    term.setTextColor(colors.lightBlue)
                end
            end
            term.write(" > " .. name .. string.rep(" ", 15 - #name))
            if term.isColor() then
                if i == selected then term.setTextColor(colors.black) end
                term.setTextColor(i == selected and colors.black or colors.gray)
            end
            -- description (truncated to fit)
            local rem = w - 4 - 15
            if rem > 0 then
                term.write((desc:sub(1, rem)))
            end
            term.setBackgroundColor(colors.black)
            term.setCursorPos(1, 4 + i)
            -- already wrote, move on
        end
        -- reset to next line
        term.setCursorPos(1, 4 + #entriesList + 1)
        if term.isColor() then term.setTextColor(colors.yellow) end
        print("")
        print(" Use arrow keys to navigate, Enter to boot.")
        print(" Or type a number 1-" .. #entriesList .. " and press Enter.")
        if term.isColor() then term.setTextColor(colors.white) end
        term.setCursorPos(1, h)
        term.write("> ")
    end

    -- Interactive loop
    local input = ""
    while true do
        render()
        -- Move cursor to bottom input line
        local w, h = term.getSize()
        term.setCursorPos(3 + #input, h)
        local event = { os.pullEvent() }
        if event[1] == "key" then
            if event[2] == keys.up then
                selected = selected - 1
                if selected < 1 then selected = #entriesList end
            elseif event[2] == keys.down then
                selected = selected + 1
                if selected > #entriesList then selected = 1 end
            elseif event[2] == keys.enter then
                return entriesList[selected]
            elseif event[2] == keys.backspace then
                input = input:sub(1, -2)
            elseif event[2] == keys.leftCtrl or event[2] == keys.rightCtrl then
                -- ignore
            end
        elseif event[1] == "char" then
            input = input .. event[2]
            -- Auto-boot if input matches a number
            local n = tonumber(input)
            if n and n >= 1 and n <= #entriesList then
                return entriesList[n]
            end
            if #input > 3 then input = input:sub(-3) end  -- cap length
        end
    end
end

function Bootloader.bootEntry(entryName)
    local entries = Bootloader.listEntries()
    local entry = entries[entryName]
    if not entry then
        if term.isColor() then term.setTextColor(colors.red) end
        print("[BOOT] Entry not found: " .. tostring(entryName))
        os.sleep(2)
        return false
    end

    log("Booting: " .. entryName)
    if term.isColor() then term.setTextColor(colors.gray) end
    print("[BOOT] Loading " .. (entry.name or entryName) .. " ...")
    if entry.description then
        print("       " .. entry.description)
    end

    -- Verify kernel file exists
    if not fs.exists(entry.kernel) then
        if term.isColor() then term.setTextColor(colors.red) end
        print("[BOOT] Kernel not found: " .. entry.kernel)
        os.sleep(3)
        return false
    end

    -- Load kernel
    local ok, kernel = pcall(dofile, entry.kernel)
    if not ok then
        if term.isColor() then term.setTextColor(colors.red) end
        print("[BOOT] Kernel load error: " .. tostring(kernel))
        os.sleep(3)
        return false
    end

    -- Kernel may be a function or a table with .run()
    if type(kernel) == "table" and kernel.run then
        kernel = kernel.run
    end

    if type(kernel) ~= "function" then
        if term.isColor() then term.setTextColor(colors.red) end
        print("[BOOT] Kernel is not callable: " .. type(kernel))
        os.sleep(3)
        return false
    end

    -- Hand off to kernel with full context
    local args = entry.args or {}
    local ctx = {
        entry      = entry,
        name       = entryName,
        bios       = _G.BIOS,
        bootloader = Bootloader,
        args       = args,
    }
    -- Stash for kernel access
    _G.BOOT_CONTEXT = ctx

    local ok2, err = pcall(kernel, ctx)
    if not ok2 then
        if term.isColor() then term.setTextColor(colors.red) end
        print("")
        print("[BOOT] Kernel panic: " .. tostring(err))
        print("")
        if term.isColor() then term.setTextColor(colors.yellow) end
        print("  System halted. Press Ctrl+R to reboot, Ctrl+T for shell.")
        -- Halt - wait for user action
        while true do
            local ev = {os.pullEvent()}
            if ev[1] == "key" and ev[2] == keys.leftCtrl then
                -- Will be combined with 'r' or 't' - just continue
            end
            os.sleep(0)
        end
    end
    return true
end

function Bootloader.run()
    -- First, load and run the BIOS (if not already done)
    if not _G.BIOS then
        if fs.exists("/bios/bios.lua") then
            local ok, bios = pcall(dofile, "/bios/bios.lua")
            if ok and bios and bios.run then
                bios.run()
            end
        end
    end

    -- Determine which entry to boot.
    -- Always show the GRUB-like menu when there are multiple entries
    -- (archos + craftos), so the user can pick.
    local entries = Bootloader.listEntries()
    local entryCount = 0
    for _ in pairs(entries) do entryCount = entryCount + 1 end

    local selected
    if entryCount > 1 then
        selected = Bootloader.showMenu(entries)
    else
        selected = Bootloader.getDefault()
        if term.isColor() then term.setTextColor(colors.gray) end
        print("[BOOT] Default entry: " .. selected)
    end

    Bootloader.bootEntry(selected)
end

return Bootloader
