--[[
    bootloader/bootloader.lua  —  OS-agnostic bootloader (v2)
    ===========================================================
    GRUB-like boot menu with number key navigation.
    F-keys replaced with number keys (1, 2, etc.)
]]

local Bootloader = {}

local BOOT_ENTRIES_DIR = "/bootloader/entries"
local BOOT_DEFAULT_FILE = "/bootloader/default"

local function log(msg)
    if _G.BIOS and _G.BIOS.log then
        _G.BIOS.log("[BOOT] " .. msg)
    end
end

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
                end
            end
        end
    end
    if not entries["archos"] then
        entries["archos"] = {
            name = "ArchOS-CC",
            kernel = "/kernel/init.lua",
            init = "/sbin/init.lua",
            description = "Arch Linux style OS for CC:Tweaked"
        }
    end
    if not entries["craftos"] then
        entries["craftos"] = {
            name = "CraftOS 1.9",
            kernel = "/kernel/craftos-shim.lua",
            description = "Boot into the standard CraftOS 1.9 shell"
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
    if _G.BIOS and _G.BIOS.config and _G.BIOS.config.defaultBoot then
        return _G.BIOS.config.defaultBoot
    end
    return "archos"
end

-- Simple, clean boot menu. Number keys to select, Enter to boot.
function Bootloader.showMenu(entries)
    local entriesList = {}
    for name, _ in pairs(entries) do
        table.insert(entriesList, name)
    end
    table.sort(entriesList)

    local selected = 1
    local def = Bootloader.getDefault()
    for i, name in ipairs(entriesList) do
        if name == def then selected = i; break end
    end

    local function render()
        local w, h = term.getSize()
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)

        -- Header
        if term.isColor() then
            term.setTextColor(colors.cyan)
            term.setBackgroundColor(colors.blue)
        end
        local header = " GNU GRUB  -  ArchOS-CC Bootloader"
        term.write(header .. string.rep(" ", math.max(0, w - #header)))
        term.setBackgroundColor(colors.black)
        if term.isColor() then term.setTextColor(colors.gray) end
        term.setCursorPos(1, 2)
        term.write(string.rep("=", w))

        -- Menu items
        if term.isColor() then term.setTextColor(colors.lightGray) end
        term.setCursorPos(1, 4)
        print(" Select an OS to boot:")
        print("")

        for i, name in ipairs(entriesList) do
            local entry = entries[name]
            local desc = entry.description or ""
            local line = name .. string.rep(" ", math.max(1, 16 - #name)) .. desc
            if #line > w - 2 then line = line:sub(1, w - 2) end

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
            term.setCursorPos(2, 6 + i)
            term.write(" " .. i .. ". " .. line .. string.rep(" ", w - #line - 4))
            term.setBackgroundColor(colors.black)
            if term.isColor() then term.setTextColor(colors.white) end
        end

        -- Footer
        term.setCursorPos(1, h - 2)
        if term.isColor() then term.setTextColor(colors.yellow) end
        print(" Up/Down: navigate  Enter: boot  or press 1-" .. #entriesList)
        if term.isColor() then term.setTextColor(colors.white) end
        term.setCursorPos(1, h)
        term.write("> ")
    end

    local input = ""
    while true do
        render()
        local w, h = term.getSize()
        term.setCursorPos(3 + #input, h)
        local event = { os.pullEvent() }
        if event[1] == "key" then
            if event[2] == keys.up then
                selected = selected - 1
                if selected < 1 then selected = #entriesList end
                input = ""
            elseif event[2] == keys.down then
                selected = selected + 1
                if selected > #entriesList then selected = 1 end
                input = ""
            elseif event[2] == keys.enter then
                return entriesList[selected]
            elseif event[2] == keys.backspace then
                input = input:sub(1, -2)
            end
        elseif event[1] == "char" then
            local n = tonumber(event[2])
            if n and n >= 1 and n <= #entriesList then
                return entriesList[n]
            end
            input = input .. event[2]
            if #input > 3 then input = input:sub(-3) end
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

    if not fs.exists(entry.kernel) then
        if term.isColor() then term.setTextColor(colors.red) end
        print("[BOOT] Kernel not found: " .. entry.kernel)
        os.sleep(3)
        return false
    end

    local ok, kernel = pcall(dofile, entry.kernel)
    if not ok then
        if term.isColor() then term.setTextColor(colors.red) end
        print("[BOOT] Kernel load error: " .. tostring(kernel))
        os.sleep(3)
        return false
    end

    if type(kernel) == "table" and kernel.run then
        kernel = kernel.run
    end

    if type(kernel) == "function" then
        local args = entry.args or {}
        local ctx = {
            entry = entry, name = entryName,
            bios = _G.BIOS, bootloader = Bootloader, args = args,
        }
        _G.BOOT_CONTEXT = ctx
        local ok2, err = pcall(kernel, ctx)
        if not ok2 then
            if term.isColor() then term.setTextColor(colors.red) end
            print("")
            print("[BOOT] Kernel panic: " .. tostring(err))
            print("")
            if term.isColor() then term.setTextColor(colors.yellow) end
            print("  Press Ctrl+R to reboot, Ctrl+T for shell.")
            while true do os.sleep(1) end
        end
        return true
    else
        if term.isColor() then term.setTextColor(colors.gray) end
        print("[BOOT] Kernel script completed.")
        return true
    end
end

function Bootloader.run()
    if not _G.BIOS then
        if fs.exists("/bios/bios.lua") then
            local ok, bios = pcall(dofile, "/bios/bios.lua")
            if ok and bios and bios.run then bios.run() end
        end
    end

    while true do
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

        term.setBackgroundColor(colors.black)
        if term.isColor() then term.setTextColor(colors.yellow) end
        print("")
        print("[BOOT] Kernel exited. Returning to boot menu in 2s...")
        if term.isColor() then term.setTextColor(colors.white) end
        os.sleep(2)
    end
end

return Bootloader
