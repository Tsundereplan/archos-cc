--[[
    startup.lua  —  ArchOS-CC entry point
    =======================================
    This file is automatically executed by ComputerCraft: Tweaked when the
    computer boots. It does the minimum work required to hand control over
    to the ArchOS-CC bootloader.

    Responsibilities:
      1. Stash the original CraftOS environment (we don't delete it, we
         shadow it via /bin/sh.lua and /lib/*).
      2. Print a short boot banner.
      3. Load /bootloader/bootloader.lua and run it. The bootloader is
         OS-agnostic: it scans /bootloader/entries/ for installed systems
         and lets the user pick one. ArchOS-CC is just one of them.

    Special mode:
      If /tmp/boot-craftos-once marker file exists (created by the
      craftos bootloader entry), we skip everything and launch the
      vanilla CraftOS shell directly. This is needed because ArchOS-CC
      pollutes _G with custom APIs that break the vanilla require().
]]

local function setColor(c)
    if term.isColor() then term.setTextColor(c) end
end

-- Quiet the screen and reset
term.clear()
term.setCursorPos(1, 1)
setColor(colors.lightBlue)
print("    ___                     ____   ____  _  __")
print("   /   | ______ __ ___     /  _/  / __ \\/ |/ /")
print("  / /| |/ __/ / / // (_-<    / /   / /_/ /    / ")
print(" /_/ |_|/_/  /_//_/___/   /___/  /____/_/|_/  ")
setColor(colors.gray)
print("  startup -> bootloader")
print("")

-- Check for restore-startup marker (from craftos-shim)
-- If /startup.lua was moved to .bak, restore it now.
if fs.exists("/tmp/restore-startup") then
    fs.delete("/tmp/restore-startup")
    if fs.exists("/startup.lua.bak") and not fs.exists("/startup.lua") then
        fs.move("/startup.lua.bak", "/startup.lua")
        -- Now re-run ourselves (the real startup)
        os.reboot()
        return
    end
end

-- Check for one-shot vanilla CraftOS boot marker
if fs.exists("/tmp/boot-craftos-once") then
    fs.delete("/tmp/boot-craftos-once")
    -- We already moved startup.lua to .bak in craftos-shim.
    -- Just reboot - CC:T will boot vanilla shell without startup.lua.
    os.reboot()
    return
end

-- Sanity check: is the bootloader present?
if not fs.exists("/bootloader/bootloader.lua") then
    setColor(colors.red)
    print("[FATAL] /bootloader/bootloader.lua not found!")
    print("        The system cannot continue booting.")
    print("")
    setColor(colors.yellow)
    print("  Possible reasons:")
    print("    * ArchOS-CC was not installed yet (run installer)")
    print("    * The bootloader file was deleted")
    print("    * Disk corruption - run a disk-check from another computer")
    print("")
    setColor(colors.white)
    print("  Falling back to CraftOS shell in 5 seconds...")
    os.sleep(5)
    -- Fall back to the default CraftOS shell (do nothing, CC will load shell)
    return
end

-- Check for pending update. If /tmp/update.pending exists, we boot into
-- update mode instead of normal boot. The file contains the repo URL,
-- the new version, and the list of files to download.
if fs.exists("/tmp/update.pending") then
    setColor(colors.yellow)
    print("[startup] Update pending - entering update mode ...")
    setColor(colors.white)
    print("")
    -- Try to run the updater script
    if fs.exists("/sbin/updater.lua") then
        local uOk, uErr = pcall(function()
            dofile("/sbin/updater.lua")
        end)
        if not uOk then
            setColor(colors.red)
            print("[startup] Updater crashed: " .. tostring(uErr))
            print("")
            -- Remove the pending file so we don't loop forever.
            -- The user can fix the issue (e.g. free disk space)
            -- and run 'update install' again.
            fs.delete("/tmp/update.pending")
            setColor(colors.yellow)
            print("  Removed /tmp/update.pending to avoid boot loop.")
            print("  Falling back to normal boot in 5 seconds...")
            os.sleep(5)
        end
    else
        setColor(colors.red)
        print("[startup] /sbin/updater.lua not found - skipping update.")
        print("  The pending update file will be removed.")
        fs.delete("/tmp/update.pending")
        os.sleep(3)
    end
end

-- Load and run the bootloader
setColor(colors.gray)
print("[startup] Handing off to bootloader ...")
local ok, err = pcall(function()
    local bootloader = dofile("/bootloader/bootloader.lua")
    if type(bootloader) == "function" then
        bootloader()
    elseif type(bootloader) == "table" and bootloader.run then
        bootloader.run()
    end
end)

if not ok then
    setColor(colors.red)
    print("[FATAL] Bootloader crashed: " .. tostring(err))
    print("")
    setColor(colors.yellow)
    print("  Falling back to vanilla CraftOS shell in 5 seconds...")
    print("  Press Ctrl+T to terminate, Ctrl+R to reboot.")
    os.sleep(5)
    -- Actively launch the vanilla CraftOS shell so the user has a
    -- working terminal to inspect / fix things from.
    -- Try /rom/programs/shell.lua first (standard CC:T path).
    local shellPath = "/rom/programs/shell.lua"
    if not fs.exists(shellPath) then
        shellPath = "/rom/programs/shell"
    end
    if fs.exists(shellPath) then
        setColor(colors.white)
        print("")
        print("[startup] Launching " .. shellPath .. " ...")
        print("")
        os.run(_G, shellPath)
    else
        setColor(colors.red)
        print("[startup] Could not find " .. shellPath)
        print("  Type os.reboot() to restart, os.shutdown() to power off.")
        setColor(colors.white)
    end
end
