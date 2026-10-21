--[[
    bin/gui-to-monitor.lua  —  Redirect GUI Desktop to a Monitor block
    ================================================================
    Launches the ArchOS-CC GUI desktop on an attached Monitor block
    instead of the computer's built-in screen.

    The monitor acts as the main display - all windows, menus, and
    apps appear on the monitor. Mouse/keyboard input still comes from
    the computer's terminal.

    Usage:
        gui-to-monitor                  Interactive (pick monitor)
        gui-to-monitor <side>           Use monitor at <side>
        gui-to-monitor --list           List attached monitors

    How it works:
      1. Wraps the monitor peripheral
      2. Sets term.redirect(monitor) so ALL output goes to monitor
      3. Runs /de/gui.lua - it draws on the monitor
      4. Input events (mouse_click, key, char) are delivered from
         the computer's terminal to the DE

    Requirements:
      * Advanced Monitor (color) for full experience
      * Monitor must be at least 30x15 for usable desktop
]]

local function setColor(c)
    if c and term.isColor() then pcall(function() term.setTextColor(c) end) end
end

local args = arg or {...}

-- Find monitors
local function findMonitors()
    local monitors = {}
    local sides = {"top","bottom","left","right","front","back"}
    for _, side in ipairs(sides) do
        if peripheral.isPresent(side) and peripheral.getType(side) == "monitor" then
            local m = peripheral.wrap(side)
            local w, h = m.getSize()
            local advanced = m.isColor and m.isColor() or false
            table.insert(monitors, {side=side, wrap=m, w=w, h=h, advanced=advanced})
        end
    end
    if peripheral.getNames then
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "monitor"
               and not (name=="top" or name=="bottom" or name=="left"
                        or name=="right" or name=="front" or name=="back") then
                local m = peripheral.wrap(name)
                local w, h = m.getSize()
                local advanced = m.isColor and m.isColor() or false
                table.insert(monitors, {side=name, wrap=m, w=w, h=h, advanced=advanced})
            end
        end
    end
    return monitors
end

if args[1] == "--list" then
    local monitors = findMonitors()
    if #monitors == 0 then
        print("No monitors attached.")
        return 1
    end
    print("Attached monitors:")
    for i, m in ipairs(monitors) do
        print(string.format("  %d. %-10s  %dx%d  %s", i, m.side, m.w, m.h,
            m.advanced and "color" or "mono"))
    end
    return 0
end

if #args == 0 or args[1] == "-h" then
    print("Usage: gui-to-monitor [side]")
    print("  Launches the GUI desktop on an external Monitor block.")
    print("  Without args: interactive mode (pick from list).")
    print("  --list: show attached monitors")
    return 0
end

local side = args[1]
local monitors = findMonitors()
local monitor = nil
for _, m in ipairs(monitors) do
    if m.side == side then monitor = m; break end
end
if not monitor then
    io.stderr:write("gui-to-monitor: no monitor at '" .. side .. "'\n")
    return 1
end

-- Check minimum size
if monitor.w < 30 or monitor.h < 15 then
    setColor(colors.yellow)
    print("WARNING: Monitor is only " .. monitor.w .. "x" .. monitor.h)
    print("  Minimum recommended: 30x15. UI may be cramped.")
    if not monitor.advanced then
        print("  Also: this is a BASIC monitor (no color). GUI will be limited.")
    end
    setColor(colors.white)
    print("")
    term.write("Continue anyway? [y/N] ")
    local ans = read()
    if ans:lower() ~= "y" then return 0 end
end

-- Set up the monitor as the primary display
setColor(colors.cyan)
print("Launching GUI on monitor at " .. side .. " ...")
setColor(colors.white)

-- Clear the monitor
monitor.wrap.setBackgroundColor(colors.black)
monitor.wrap.setTextColor(colors.white)
monitor.wrap.clear()
monitor.wrap.setCursorPos(1, 1)

-- Redirect term to the monitor
local oldRedirect = term.redirect(monitor.wrap)

-- Run the GUI
local ok, err = pcall(function()
    dofile("/de/gui.lua")
end)

-- Restore
term.redirect(oldRedirect)

if not ok then
    setColor(colors.red)
    print("[gui-to-monitor] GUI crashed: " .. tostring(err))
    setColor(colors.white)
    return 1
end

return 0
