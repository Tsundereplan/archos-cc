--[[
    usr/bin/monitor-cast.lua  —  Cast screen to a Monitor block
    ============================================================
    Captures the current terminal output and renders it on an
    attached Monitor peripheral. Useful for displaying artwork,
    system info, or any program's output on a larger screen.

    Usage:
        monitor-cast                  Interactive mode (pick monitor)
        monitor-cast <side>           Cast to monitor at <side>
        monitor-cast <side> --file <path>   Display an NFP image file
        monitor-cast <side> --text "Hello"  Display text
        monitor-cast <side> --clear         Clear the monitor
        monitor-cast --list                 List attached monitors

    How it works:
      * Wraps the monitor peripheral via peripheral.wrap(side)
      * Uses term.redirect(monitor) so all term calls go to monitor
      * Runs your program or displays text/image
      * Restores term.redirect when done

    Images must be in NFP format (CC:Tweaked paint format):
      - One color index per character per line
      - Use 'paint' to create them
]]

local function setColor(c)
    if c and term.isColor() then pcall(function() term.setTextColor(c) end) end
end

local args = arg or {...}

-- Find all attached monitors
local function findMonitors()
    local monitors = {}
    local sides = {"top", "bottom", "left", "right", "front", "back"}
    for _, side in ipairs(sides) do
        if peripheral.isPresent(side) and peripheral.getType(side) == "monitor" then
            table.insert(monitors, side)
        end
    end
    if peripheral.getNames then
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "monitor"
               and name ~= "top" and name ~= "bottom"
               and name ~= "left" and name ~= "right"
               and name ~= "front" and name ~= "back" then
                table.insert(monitors, name)
            end
        end
    end
    return monitors
end

-- List monitors
if args[1] == "--list" then
    local monitors = findMonitors()
    if #monitors == 0 then
        print("No monitors attached.")
        print("Place a Monitor block next to the computer and try again.")
        return 1
    end
    print("Attached monitors:")
    for i, side in ipairs(monitors) do
        local m = peripheral.wrap(side)
        local w, h = m.getSize()
        local advanced = m.isColor and m.isColor() or false
        print(string.format("  %d. %-10s  %dx%d  %s",
            i, side, w, h, advanced and "color" or "mono"))
    end
    return 0
end

if #args == 0 or args[1] == "-h" or args[1] == "--help" then
    print("Usage: monitor-cast [options]")
    print("")
    print("Options:")
    print("  --list                    List attached monitors")
    print("  <side>                    Cast to monitor at <side>")
    print("  <side> --file <path>      Display an NFP image file")
    print("  <side> --text \"message\"   Display text")
    print("  <side> --clear            Clear the monitor")
    print("")
    print("Without args: interactive mode (pick from list)")
    return 0
end

local side = args[1]
local monitors = findMonitors()
local found = false
for _, s in ipairs(monitors) do
    if s == side then found = true; break end
end
if not found then
    io.stderr:write("monitor-cast: no monitor at '" .. side .. "'\n")
    io.stderr:write("Available monitors:\n")
    for _, s in ipairs(monitors) do
        io.stderr:write("  " .. s .. "\n")
    end
    return 1
end

local monitor = peripheral.wrap(side)
if not monitor then
    io.stderr:write("monitor-cast: could not wrap monitor at " .. side .. "\n")
    return 1
end

-- Determine action
local action = args[2] or "--interactive"
if action == "--clear" then
    monitor.clear()
    monitor.setCursorPos(1, 1)
    print("Monitor cleared.")
    return 0
end

if action == "--text" then
    local text = args[3] or ""
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()
    monitor.setCursorPos(1, 1)
    -- Word-wrap
    local w, h = monitor.getSize()
    local line = ""
    for word in text:gmatch("%S+") do
        if #line + #word + 1 > w then
            monitor.write(line)
            local _, y = monitor.getCursorPos()
            if y >= h then break end
            monitor.setCursorPos(1, y + 1)
            line = word
        else
            if line == "" then line = word
            else line = line .. " " .. word end
        end
    end
    if line ~= "" then monitor.write(line) end
    print("Text displayed on monitor " .. side)
    return 0
end

if action == "--file" then
    local path = args[3]
    if not path or not fs.exists(path) then
        io.stderr:write("monitor-cast: file not found: " .. tostring(path) .. "\n")
        return 1
    end
    -- Try to load as NFP image
    local image = paintutils.loadImage(path)
    if not image then
        io.stderr:write("monitor-cast: could not load image (not an NFP file?)\n")
        return 1
    end
    -- Draw on monitor
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    paintutils.drawImage(image, 1, 1)
    print("Image displayed on monitor " .. side)
    return 0
end

-- Default: interactive mode - redirect term to monitor and run a program
print("Casting to monitor at " .. side .. " ...")
print("Type commands to run on the monitor. Type 'exit' to stop.")
print("")
local oldRedirect = term.redirect(monitor)
monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
monitor.clear()
monitor.setCursorPos(1, 1)
-- Run shell on monitor
while true do
    local _, y = monitor.getCursorPos()
    local w, h = monitor.getSize()
    if y > h - 1 then
        monitor.scroll(1)
        monitor.setCursorPos(1, h - 1)
    end
    monitor.setTextColor(colors.lightBlue)
    monitor.write("> ")
    monitor.setTextColor(colors.white)
    -- Read input from the main computer terminal (since monitor can't accept input)
    term.redirect(oldRedirect)
    local line = read()
    if not line or line == "exit" then
        break
    end
    term.redirect(monitor)
    -- Run the command on the monitor
    local ok, err = pcall(function()
        shell.run(line)
    end)
    if not ok then
        monitor.setTextColor(colors.red)
        monitor.write("Error: " .. tostring(err) .. "\n")
        monitor.setTextColor(colors.white)
    end
end
term.redirect(oldRedirect)
print("Stopped casting.")
return 0
