--[[
    bin/install-to-disk.lua  —  Install ArchOS-CC to a floppy disk
    ===================================================================
    Copies the running ArchOS-CC system to a floppy disk, making it
    bootable. The disk can then be used to install ArchOS-CC on any
    other Advanced Computer with a Disk Drive.

    Usage:
        install-to-disk                 Interactive mode (choose drive)
        install-to-disk <side>          Install to drive at <side>
        install-to-disk <side> --label "ArchOS-CC Install"
        install-to-disk --list          List available disk drives

    After install:
      1. Eject the disk from the source computer
      2. Place it in a Disk Drive next to a fresh Advanced Computer
      3. The fresh computer will auto-boot from the disk (if no /startup.lua)
      4. From the disk's startup, you can run /disk/installer.lua to install

    The disk will contain:
      - All system files (kernel/, bin/, lib/, etc.)
      - A startup.lua that launches the installer
      - installer.lua (the GitHub installer, in case the disk needs
        to re-download anything)
]]

local function setColor(c)
    if c and term.isColor() then pcall(function() term.setTextColor(c) end) end
end

local function setBG(c)
    if c and term.isColor() then pcall(function() term.setBackgroundColor(c) end) end
end

local function resetColors()
    setBG(colors.black)
    setColor(colors.white)
end

-- Find all disk drives connected
local function findDiskDrives()
    local drives = {}
    local sides = {"top", "bottom", "left", "right", "front", "back"}
    for _, side in ipairs(sides) do
        if peripheral.isPresent(side) and peripheral.getType(side) == "drive" then
            local drive = peripheral.wrap(side)
            local hasDisk = false
            if drive and drive.hasDisk then
                local ok, res = pcall(drive.hasDisk)
                if ok then hasDisk = res end
            end
            table.insert(drives, { side = side, wrap = drive, hasDisk = hasDisk })
        end
    end
    -- Also check peripherals connected via wired modems (peripheral.getNames())
    if peripheral.getNames then
        for _, name in ipairs(peripheral.getNames()) do
            local ptype = peripheral.getType(name)
            if ptype == "drive" and name ~= "top" and name ~= "bottom"
               and name ~= "left" and name ~= "right"
               and name ~= "front" and name ~= "back" then
                local drive = peripheral.wrap(name)
                local hasDisk = false
                if drive and drive.hasDisk then
                    local ok, res = pcall(drive.hasDisk)
                    if ok then hasDisk = res end
                end
                table.insert(drives, { side = name, wrap = drive, hasDisk = hasDisk })
            end
        end
    end
    return drives
end

-- Get the CC:Tweaked mount path for a disk drive
-- Disks mount to /disk, /disk2, /disk3, etc.
local function getDiskMountPath(side)
    local drive = peripheral.wrap(side)
    if not drive then return nil end
    -- Try getMountPath (works on newer CC:T versions)
    if drive.getMountPath then
        local ok, path = pcall(drive.getMountPath)
        if ok and path then return path end
    end
    -- Fallback: try to figure it out from disk ID
    if drive.getDiskID then
        local ok, id = pcall(drive.getDiskID)
        if ok and id ~= nil then
            if id == 0 then return "/disk" end
            return "/disk" .. (id + 1)
        end
    end
    -- Last resort: scan for /disk, /disk2, ... and find the newest
    for i = 0, 20 do
        local path = i == 0 and "/disk" or "/disk" .. (i + 1)
        if fs.exists(path) then
            -- Found a mounted disk
            return path
        end
    end
    return nil
end

-- List of files/dirs to copy (the entire OS)
local SYSTEM_PATHS = {
    "startup.lua",
    "installer.lua",
    "bios",
    "bootloader",
    "kernel",
    "lib",
    "bin",
    "sbin",
    "usr",
    "de",
    "etc",
    "docs",
    "latest_update.upd",
    "MANIFEST",
    "README.md",
    "LICENSE",
    "QUICKSTART.md",
    ".gitignore",
}

-- Recursive copy
local function copyTree(src, dst, progressCb)
    if not fs.exists(src) then return true end
    if fs.isDir(src) then
        if not fs.exists(dst) then fs.makeDir(dst) end
        for _, name in ipairs(fs.list(src)) do
            local s = src .. "/" .. name
            local d = dst .. "/" .. name
            if not copyTree(s, d, progressCb) then
                return false
            end
        end
    else
        -- Check disk space
        local size = fs.getSize(src)
        local free = fs.getFreeSpace(fs.getDir(dst) or "/")
        if free and free < size + 100 then
            return false, "out of disk space on floppy"
        end
        local ok = pcall(fs.copy, src, dst)
        if not ok then return false, "copy failed: " .. src end
        if progressCb then progressCb(src) end
    end
    return true
end

-- Count total size and file count
local function countTree(path)
    if not fs.exists(path) then return 0, 0 end
    if not fs.isDir(path) then return fs.getSize(path), 1 end
    local total = 0
    local files = 0
    for _, name in ipairs(fs.list(path)) do
        local s, f = countTree(path .. "/" .. name)
        total = total + s
        files = files + f
    end
    return total, files
end

-- Bootable startup.lua for the install disk.
-- When booted from disk, this presents a menu:
--   1. Install ArchOS-CC to this computer
--   2. Drop to vanilla CraftOS shell
--   3. Reboot
-- We use [===[ ]===] (3 equals) as the outer string delimiter so the
-- inner Lua code can freely use [==[ ]==] (2 equals) for its own
-- long strings without confusing the parser.
local BOOTABLE_STARTUP = [===[
--[[
    ArchOS-CC Install Disk  -  Boot Sector
    =======================================
    This disk is bootable. When a computer boots from it (no local
    /startup.lua present), this script runs and offers to install
    ArchOS-CC to that computer.
]]

local function setColor(c)
    if c and term.isColor() then pcall(function() term.setTextColor(c) end) end
end

local function setBG(c)
    if c and term.isColor() then pcall(function() term.setBackgroundColor(c) end) end
end

-- Find the disk's own path (the path this startup is running from).
-- We try /disk, /disk2, ..., /disk10.
local function findDiskPath()
    for i = 0, 10 do
        local p = i == 0 and "/disk" or "/disk" .. (i + 1)
        if fs.exists(p .. "/archos-disk.marker") then
            return p
        end
    end
    return nil
end

local function main()
    local diskPath = findDiskPath()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)

    setColor(colors.lightBlue)
    print("    ___               ____   ____  _  __")
    print("   /   | ______ __ ___/  _/  / __ \\/ |/ /")
    print("  / /| |/ __/ / // (_-< /    / /_/ /    /  ")
    print(" /_/ |_|/_/  /_//_/___/___/  /____/_/|_/  ")
    setColor(colors.lightGray)
    print(" Install Disk  -  Arch Linux style OS for CC:Tweaked")
    print("")
    setColor(colors.white)

    if not diskPath then
        setColor(colors.red)
        print("[ERR] Could not find ArchOS-CC disk marker.")
        print("      Make sure this disk was created by 'install-to-disk'.")
        print("")
        setColor(colors.yellow)
        print("  Falling back to CraftOS shell in 3 seconds...")
        setColor(colors.white)
        os.sleep(3)
        os.run(_G, "/rom/programs/shell.lua")
        return
    end

    setColor(colors.cyan)
    print("Disk path: " .. diskPath)
    setColor(colors.white)
    print("")
    print("Choose an option:")
    print("  1) Install ArchOS-CC to this computer")
    print("  2) Run from disk (live mode - no install)")
    print("  3) Vanilla CraftOS shell")
    print("  4) Reboot")
    print("  5) Power off")
    print("")
    setColor(colors.yellow)
    term.write("Choice [1-5]: ")
    setColor(colors.white)
    local c = read()
    print("")

    if c == "1" then
        -- Install: copy all files from disk to local /
        setColor(colors.cyan)
        print("Installing ArchOS-CC from disk ...")
        print("")
        local itemsToCopy = {
            "startup.lua", "installer.lua",
            "bios", "bootloader", "kernel", "lib", "bin", "sbin",
            "usr", "de", "etc", "docs", "latest_update.upd",
            "MANIFEST", "README.md", "LICENSE", "QUICKSTART.md",
            ".gitignore",
        }
        local function copyTree(src, dst)
            if not fs.exists(src) then return true end
            if fs.isDir(src) then
                if not fs.exists(dst) then fs.makeDir(dst) end
                for _, name in ipairs(fs.list(src)) do
                    if not copyTree(src .. "/" .. name, dst .. "/" .. name) then
                        return false
                    end
                end
                return true
            else
                local ok = pcall(fs.copy, src, dst)
                return ok
            end
        end
        local count = 0
        local failed = 0
        for _, item in ipairs(itemsToCopy) do
            local src = diskPath .. "/" .. item
            local dst = "/" .. item
            if fs.exists(src) then
                setColor(colors.green)
                term.write("  [COPY] " .. item .. " ... ")
                local ok = copyTree(src, dst)
                if ok then
                    setColor(colors.green); print("OK")
                    count = count + 1
                else
                    setColor(colors.red); print("FAIL")
                    failed = failed + 1
                end
            end
        end
        print("")
        setColor(colors.lightBlue)
        print("========================================")
        setColor(colors.green)
        print(string.format("  Copied: %d items", count))
        if failed > 0 then
            setColor(colors.red)
            print(string.format("  Failed: %d items", failed))
        end
        setColor(colors.lightBlue)
        print("========================================")
        print("")
        setColor(colors.green)
        print("Installation complete! Remove disk and reboot.")
        setColor(colors.yellow)
        print("Rebooting in 3 seconds...")
        setColor(colors.white)
        os.sleep(3)
        os.reboot()
    elseif c == "2" then
        -- Live mode: run from disk
        setColor(colors.cyan)
        print("Starting ArchOS-CC in live mode ...")
        print("(Changes will NOT be saved to the disk)")
        print("")
        -- Run the disk's startup-archos.lua
        local liveStartup = diskPath .. "/startup-archos.lua"
        if fs.exists(liveStartup) then
            os.run(_G, liveStartup)
        else
            setColor(colors.red)
            print("Live mode requires /startup-archos.lua on disk.")
            setColor(colors.white)
        end
    elseif c == "3" then
        os.run(_G, "/rom/programs/shell.lua")
    elseif c == "4" then
        os.reboot()
    elseif c == "5" then
        os.shutdown()
    else
        print("Invalid choice.")
        os.sleep(2)
    end
end

return main()
]===]

-- Live-mode startup (runs ArchOS-CC from disk without installing)
local LIVE_STARTUP = [===[
-- Live-mode ArchOS-CC startup (runs from disk, doesn't install)
-- This file is named /disk/startup-archos.lua and is invoked when
-- the user picks "Run from disk" from the boot menu.

_G.ARCHOS_LIVE_MODE = true
_G.ARCHOS_LIVE_ROOT = "/disk"

-- Find the disk path
for i = 0, 10 do
    local p = i == 0 and "/disk" or "/disk" .. (i + 1)
    if fs.exists(p .. "/kernel/init.lua") then
        _G.ARCHOS_LIVE_ROOT = p
        break
    end
end

print("[live] Booting ArchOS-CC from " .. _G.ARCHOS_LIVE_ROOT .. " ...")
os.sleep(1)

-- Run the kernel
local kernelPath = _G.ARCHOS_LIVE_ROOT .. "/kernel/init.lua"
if fs.exists(kernelPath) then
    os.run(_G, kernelPath)
else
    print("[live] Kernel not found at " .. kernelPath)
    print("  Falling back to CraftOS shell.")
    os.run(_G, "/rom/programs/shell.lua")
end
]===]

-- Print banner
local function banner()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    setColor(colors.lightBlue)
    print("    ArchOS-CC Disk Installer")
    print("    ========================")
    setColor(colors.white)
    print("")
end

local args = arg or {...}

-- --list subcommand
if args[1] == "--list" then
    banner()
    local drives = findDiskDrives()
    if #drives == 0 then
        setColor(colors.red)
        print("No disk drives found.")
        setColor(colors.white)
        return 1
    end
    setColor(colors.cyan)
    print("Disk drives:")
    setColor(colors.white)
    for _, d in ipairs(drives) do
        local status = d.hasDisk and "disk present" or "empty"
        local label = ""
        if d.hasDisk and d.wrap and d.wrap.getDiskLabel then
            local ok, lbl = pcall(d.wrap.getDiskLabel)
            if ok and lbl then label = " (label: " .. tostring(lbl) .. ")" end
        end
        print(string.format("  %-10s %s%s", d.side, status, label))
    end
    return 0
end

local function main()
    banner()

    -- Find disk drives
    local drives = findDiskDrives()
    if #drives == 0 then
        setColor(colors.red)
        print("No disk drives found on this computer.")
        print("")
        setColor(colors.yellow)
        print("  Attach a Disk Drive peripheral next to this computer")
        print("  and insert a Floppy Disk, then run this command again.")
        setColor(colors.white)
        return 1
    end

    -- Pick a drive
    local drive
    if args[1] and args[1] ~= "" and args[1] ~= "--label" then
        -- Use specified side
        for _, d in ipairs(drives) do
            if d.side == args[1] then drive = d; break end
        end
        if not drive then
            setColor(colors.red)
            print("No disk drive at: " .. args[1])
            print("Use 'install-to-disk --list' to see available drives.")
            setColor(colors.white)
            return 1
        end
    else
        -- Interactive: list and pick
        setColor(colors.cyan)
        print("Available disk drives:")
        setColor(colors.white)
        for i, d in ipairs(drives) do
            local status = d.hasDisk and "disk present" or "empty"
            local label = ""
            if d.hasDisk and d.wrap and d.wrap.getDiskLabel then
                local ok, lbl = pcall(d.wrap.getDiskLabel)
                if ok and lbl then label = " (label: " .. tostring(lbl) .. ")" end
            end
            print(string.format("  %d. %-10s %s%s", i, d.side, status, label))
        end
        print("")
        setColor(colors.yellow)
        term.write("Select drive (1-" .. #drives .. "): ")
        setColor(colors.white)
        local c = read()
        local n = tonumber(c)
        if not n or n < 1 or n > #drives then
            setColor(colors.red)
            print("Invalid selection.")
            setColor(colors.white)
            return 1
        end
        drive = drives[n]
    end

    -- Check disk is present
    if not drive.hasDisk then
        setColor(colors.red)
        print("No disk in drive at " .. drive.side)
        print("")
        setColor(colors.yellow)
        print("  Insert a Floppy Disk and try again.")
        setColor(colors.white)
        return 1
    end

    -- Find mount path
    local mountPath = getDiskMountPath(drive.side)
    if not mountPath then
        setColor(colors.red)
        print("Could not determine mount path for disk at " .. drive.side)
        print("  Make sure the disk is properly mounted.")
        setColor(colors.white)
        return 1
    end

    setColor(colors.cyan)
    print("Disk mount path: " .. mountPath)
    setColor(colors.white)
    print("")

    -- Check disk space
    local diskFree = fs.getFreeSpace(mountPath)
    setColor(colors.gray)
    print("Disk free space: " .. tostring(diskFree) .. " bytes")
    setColor(colors.white)

    -- Count what we need to copy
    local totalSize = 0
    local totalFiles = 0
    for _, path in ipairs(SYSTEM_PATHS) do
        local s, f = countTree("/" .. path)
        totalSize = totalSize + s
        totalFiles = totalFiles + f
    end
    print(string.format("Need to copy: %d files, %d bytes (%.1f KB)",
        totalFiles, totalSize, totalSize / 1024))
    print("")

    if diskFree and diskFree < totalSize + 5000 then
        setColor(colors.red)
        print("[!] Not enough space on disk!")
        print("    Need: " .. (totalSize + 5000) .. " bytes")
        print("    Have: " .. diskFree .. " bytes")
        print("")
        setColor(colors.yellow)
        print("  Use a different disk, or remove some files from it first.")
        print("  Run 'cleanup' to free space on this computer if needed.")
        setColor(colors.white)
        return 1
    end

    -- Confirm
    setColor(colors.yellow)
    term.write("This will OVERWRITE all files on " .. mountPath .. ". Continue? [y/N] ")
    setColor(colors.white)
    local c = read()
    if c:lower() ~= "y" and c:lower() ~= "yes" then
        print("Cancelled.")
        return 1
    end

    -- Set disk label
    local label = "ArchOS-CC Install"
    for i, a in ipairs(args) do
        if a == "--label" and args[i+1] then
            label = args[i+1]
            break
        end
    end
    if drive.wrap and drive.wrap.setDiskLabel then
        pcall(drive.wrap.setDiskLabel, label)
        setColor(colors.gray)
        print("Disk label set to: " .. label)
        setColor(colors.white)
    end

    -- Clear disk first
    setColor(colors.cyan)
    print("Clearing disk ...")
    setColor(colors.white)
    if fs.exists(mountPath) and fs.isDir(mountPath) then
        for _, name in ipairs(fs.list(mountPath)) do
            pcall(fs.delete, mountPath .. "/" .. name)
        end
    end

    -- Copy system files
    setColor(colors.cyan)
    print("Copying system files ...")
    setColor(colors.white)
    local copied = 0
    local failed = 0
    local function showProgress(name)
        copied = copied + 1
        setColor(colors.green)
        term.write(".")
        setColor(colors.white)
        if copied % 20 == 0 then print() end
    end
    for _, path in ipairs(SYSTEM_PATHS) do
        local src = "/" .. path
        local dst = mountPath .. "/" .. path
        if fs.exists(src) then
            local ok, err = copyTree(src, dst, showProgress)
            if not ok then
                failed = failed + 1
                setColor(colors.red)
                print("\n[FAIL] " .. path .. ": " .. tostring(err))
                setColor(colors.white)
            end
        end
    end
    print("")

    -- Write bootable startup.lua
    setColor(colors.cyan)
    print("Writing bootable startup.lua ...")
    setColor(colors.white)
    local f = fs.open(mountPath .. "/startup.lua", "w")
    if f then
        f.write(BOOTABLE_STARTUP)
        f.close()
    end

    -- Write live-mode startup
    f = fs.open(mountPath .. "/startup-archos.lua", "w")
    if f then
        f.write(LIVE_STARTUP)
        f.close()
    end

    -- Write marker file (so the disk identifies itself as ArchOS install disk)
    f = fs.open(mountPath .. "/archos-disk.marker", "w")
    if f then
        f.write("ArchOS-CC Install Disk v1.0\n")
        f.close()
    end

    -- Done
    print("")
    setColor(colors.lightBlue)
    print("============================================")
    setColor(colors.green)
    print("  ArchOS-CC Install Disk created!")
    print("  Files copied: " .. copied)
    if failed > 0 then
        setColor(colors.red)
        print("  Failed:        " .. failed)
    end
    setColor(colors.lightBlue)
    print("============================================")
    setColor(colors.white)
    print("")
    setColor(colors.yellow)
    print("To use this disk:")
    print("  1. Eject from this computer")
    print("  2. Place it in a Disk Drive next to a fresh Advanced Computer")
    print("  3. Boot the new computer - it will boot from the disk")
    print("  4. Select 'Install ArchOS-CC to this computer'")
    print("")
    setColor(colors.green)
    print("Done!")
    setColor(colors.white)

    return 0
end

return main()
