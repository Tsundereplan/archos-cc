--[[
    bootloader/bootloader.lua  —  OS-agnostic bootloader (v3)
    ===========================================================
    Clean GRUB-like boot menu. Number keys + Enter.
    No rendering bugs.
]]

local Bootloader = {}
local BOOT_ENTRIES_DIR = "/bootloader/entries"
local BOOT_DEFAULT_FILE = "/bootloader/default"

local function log(msg)
    if _G.BIOS and _G.BIOS.log then _G.BIOS.log("[BOOT] " .. msg) end
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
            name="ArchOS-CC", kernel="/kernel/init.lua",
            description="Arch Linux style OS for CC:Tweaked"
        }
    end
    if not entries["craftos"] then
        entries["craftos"] = {
            name="CraftOS 1.9", kernel="/kernel/craftos-shim.lua",
            description="Boot into the standard CraftOS 1.9 shell"
        }
    end
    -- Add restore option (special entry)
    entries["restore"] = {
        name="Restore from Backup",
        kernel="__restore__",
        description="Restore system from a backup"
    }
    return entries
end

function Bootloader.getDefault()
    if fs.exists(BOOT_DEFAULT_FILE) then
        local f = fs.open(BOOT_DEFAULT_FILE, "r")
        if f then local n = f.readAll(); f.close()
            n = n:gsub("^%s+",""):gsub("%s+$","")
            if n ~= "" then return n end
        end
    end
    return "archos"
end

function Bootloader.showMenu(entries)
    local list = {}
    for name, _ in pairs(entries) do table.insert(list, name) end
    table.sort(list)

    local selected = 1
    local def = Bootloader.getDefault()
    for i, n in ipairs(list) do if n == def then selected = i break end end

    while true do
        local w, h = term.getSize()
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)

        -- Header
        if term.isColor() then
            term.setTextColor(colors.cyan)
            term.setBackgroundColor(colors.blue)
        end
        term.clearLine()
        term.write(" GNU GRUB  -  ArchOS-CC Bootloader")
        term.setBackgroundColor(colors.black)
        if term.isColor() then term.setTextColor(colors.gray) end
        term.setCursorPos(1, 2)
        term.write(string.rep("=", w))

        -- Menu items - SIMPLE, no fancy cursor tricks
        if term.isColor() then term.setTextColor(colors.lightGray) end
        term.setCursorPos(1, 4)
        term.write(" Select an OS to boot:")
        term.setCursorPos(1, 5)
        term.write("")

        for i, name in ipairs(list) do
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
            term.setCursorPos(2, 6 + i)
            local line = " " .. i .. ". " .. name .. "  " .. desc
            if #line > w - 2 then line = line:sub(1, w - 2) end
            term.write(line .. string.rep(" ", w - #line - 2))
            term.setBackgroundColor(colors.black)
        end

        -- Footer
        if term.isColor() then term.setTextColor(colors.yellow) end
        term.setCursorPos(1, h - 1)
        term.write(" Up/Down: navigate  Enter: boot  or press 1-" .. #list)
        term.setCursorPos(1, h)
        if term.isColor() then term.setTextColor(colors.white) end
        term.write("> ")

        -- Input
        local event = { os.pullEvent() }
        if event[1] == "key" then
            if event[2] == keys.up then
                selected = selected - 1
                if selected < 1 then selected = #list end
            elseif event[2] == keys.down then
                selected = selected + 1
                if selected > #list then selected = 1 end
            elseif event[2] == keys.enter then
                return list[selected]
            end
        elseif event[1] == "char" then
            local n = tonumber(event[2])
            if n and n >= 1 and n <= #list then
                return list[n]
            end
        end
    end
end

function Bootloader.bootEntry(entryName)
    local entries = Bootloader.listEntries()
    local entry = entries[entryName]

    -- Special: restore mode
    if entryName == "restore" or (entry and entry.kernel == "__restore__") then
        return Bootloader.restoreBackup()
    end

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
        local ctx = { entry=entry, name=entryName, bios=_G.BIOS, bootloader=Bootloader, args=entry.args or {} }
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
        -- Script-based kernel (craftos-shim) - already ran during dofile
        if term.isColor() then term.setTextColor(colors.gray) end
        print("[BOOT] Kernel script completed.")
        return true
    end
end

-- Restore system from backup
function Bootloader.restoreBackup()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    if term.isColor() then term.setTextColor(colors.cyan) end
    print("=== System Restore ===")
    print("")
    if term.isColor() then term.setTextColor(colors.white) end

    -- Find backups
    local backups = {}
    if fs.exists("/backup") and fs.isDir("/backup") then
        for _, name in ipairs(fs.list("/backup")) do
            if name:match("^archos") then
                table.insert(backups, "/backup/" .. name)
            end
        end
    end
    -- Also check disk
    for i = 0, 5 do
        local dp = i == 0 and "/disk" or "/disk" .. (i + 1)
        if fs.exists(dp .. "/archos-backup") or fs.exists(dp .. "/update-backup") then
            table.insert(backups, dp .. "/archos-backup")
        end
    end

    if #backups == 0 then
        if term.isColor() then term.setTextColor(colors.red) end
        print("No backups found!")
        print("")
        if term.isColor() then term.setTextColor(colors.yellow) end
        print("Backups are created in:")
        print("  /backup/archos-<timestamp>/  (local disk)")
        print("  /disk/archos-backup-<ts>/    (floppy disk)")
        print("  /disk/update-backup/         (updater backup)")
        print("")
        print("Press any key to return to boot menu...")
        if term.isColor() then term.setTextColor(colors.white) end
        os.pullEvent("key")
        return false
    end

    if term.isColor() then term.setTextColor(colors.green) end
    print("Found " .. #backups .. " backup(s):")
    if term.isColor() then term.setTextColor(colors.white) end
    for i, path in ipairs(backups) do
        print("  " .. i .. ". " .. path)
    end
    print("")
    if term.isColor() then term.setTextColor(colors.yellow) end
    term.write("Select backup to restore (1-" .. #backups .. "): ")
    if term.isColor() then term.setTextColor(colors.white) end
    local input = read()
    local idx = tonumber(input)
    if not idx or idx < 1 or idx > #backups then
        print("Invalid selection.")
        os.sleep(2)
        return false
    end

    local backupDir = backups[idx]
    if term.isColor() then term.setTextColor(colors.cyan) end
    print("")
    print("Restoring from " .. backupDir .. " ...")
    if term.isColor() then term.setTextColor(colors.white) end

    -- Copy all files from backup to /
    local function copyTree(src, dst)
        if not fs.exists(src) then return end
        if fs.isDir(src) then
            if not fs.exists(dst) then fs.makeDir(dst) end
            for _, name in ipairs(fs.list(src)) do
                copyTree(src .. "/" .. name, dst .. "/" .. name)
            end
        else
            -- Delete old file first, then copy
            if fs.exists(dst) then fs.delete(dst) end
            local ok = pcall(fs.copy, src, dst)
            if ok then
                term.write(".")
            end
        end
    end

    -- Restore each top-level dir
    for _, dir in ipairs({"kernel", "bin", "sbin", "lib", "bios", "bootloader", "de", "etc"}) do
        if fs.exists(backupDir .. "/" .. dir) then
            copyTree(backupDir .. "/" .. dir, "/" .. dir)
        end
    end
    -- Restore startup.lua
    if fs.exists(backupDir .. "/startup.lua") then
        if fs.exists("/startup.lua") then fs.delete("/startup.lua") end
        fs.copy(backupDir .. "/startup.lua", "/startup.lua")
    end

    print("")
    if term.isColor() then term.setTextColor(colors.green) end
    print("Restore complete! Rebooting in 3 seconds...")
    if term.isColor() then term.setTextColor(colors.white) end
    os.sleep(3)
    os.reboot()
    return true
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

        -- Show boot menu (always, since we have archos + craftos)
        local selected
        if entryCount > 1 then
            -- Check for 'r' key during menu for restore mode
            -- We add restore as a hidden option in the menu
            selected = Bootloader.showMenu(entries)
        else
            selected = Bootloader.getDefault()
        end

        -- Check if user wants to restore (press 'r' at menu)
        if selected == "restore" then
            Bootloader.restoreBackup()
        else
            Bootloader.bootEntry(selected)
        end

        term.setBackgroundColor(colors.black)
        if term.isColor() then term.setTextColor(colors.yellow) end
        print("")
        print("[BOOT] Kernel exited. Returning to boot menu in 2s...")
        if term.isColor() then term.setTextColor(colors.white) end
        os.sleep(2)
    end
end

return Bootloader
