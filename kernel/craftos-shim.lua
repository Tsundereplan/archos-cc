--[[
    kernel/craftos-shim.lua  —  CraftOS 1.9 vanilla shim
    ===================================================
    A minimal "kernel" that hands control directly to the
    native CraftOS shell, bypassing ArchOS-CC entirely.

    This is selected from the bootloader menu when the user
    picks "CraftOS" instead of "ArchOS-CC".

    It does NOT load:
      * ArchOS-CC process manager / scheduler
      * Virtual filesystem layer
      * Permissions / users
      * PnP drivers
      * pacman / systemd

    It DOES:
      * Reset the screen to native CraftOS look (gray text on black)
      * Print a short banner identifying CraftOS 1.9 mode
      * Find and launch the native shell (the one CraftOS ships
        with at /rom/programs/shell.lua, or via os.run / shell.run)
      * Exit back to the bootloader when the shell exits
]]

-- Reset terminal to CraftOS defaults
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)

-- Banner
if term.isColor() then
    term.setTextColor(colors.lightGray)
end
print("    CraftOS 1.9.2  -  vanilla shell mode")
print("    ======================================")
print("")
if term.isColor() then
    term.setTextColor(colors.white)
end

-- Expose minimal _G context for CraftOS shell
_G.CRAFTOS_MODE = true

-- The CraftOS shell is provided in the computer's ROM at /rom/programs/shell.lua
-- CC:Tweaked also exposes the global `shell` API once the shell is running.
-- We launch it via os.run with the standard CraftOS environment.

local shellPath = "/rom/programs/shell.lua"
if not fs.exists(shellPath) then
    -- Fallback: try the older CC location
    shellPath = "/rom/programs/shell"
end

if not fs.exists(shellPath) then
    -- Last-resort: just give the user an interactive Lua prompt
    if term.isColor() then term.setTextColor(colors.yellow) end
    print("Could not find CraftOS shell at " .. shellPath)
    print("Falling back to interactive Lua prompt.")
    print("Type os.reboot() to restart, os.shutdown() to power off.")
    if term.isColor() then term.setTextColor(colors.white) end
    while true do
        io.write("> ")
        local line = read()
        if line then
            local fn, err = load(line)
            if fn then
                local ok, rerr = pcall(fn)
                if not ok then
                    print("error: " .. tostring(rerr))
                end
            else
                print("compile error: " .. tostring(err))
            end
        end
    end
    return
end

-- Run the native CraftOS shell.
-- os.run uses the global environment, so the shell will see _G as expected.
local ok, err = os.run({}, shellPath)

if not ok then
    if term.isColor() then term.setTextColor(colors.red) end
    print("")
    print("CraftOS shell exited with error: " .. tostring(err))
    print("Returning to bootloader in 3 seconds...")
    if term.isColor() then term.setTextColor(colors.white) end
    os.sleep(3)
end

-- When the shell exits (user typed `exit`), return to the bootloader
return ok
