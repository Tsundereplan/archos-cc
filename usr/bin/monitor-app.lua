--[[
    usr/bin/monitor-app.lua  —  Monitor manager
    ==========================================
    Manage attached CC:Tweaked monitors (peripheral type "monitor").

    Usage:
      monitor-app                       List all attached monitors
      monitor-app attach <side>         Show status of a specific monitor
      monitor-app display <side> <text> Write text to a monitor
      monitor-app clear <side>          Clear a monitor
      monitor-app redirect <side>       Redirect term output to monitor, then exec /bin/sh.lua
      monitor-app resize <side> <w> <h> Set text scale (1-5; w,h args are accepted but
                                         only scale is applied - CC:T has no real resize)
      monitor-app mirror                Mirror main terminal to all attached monitors
]]

local args = arg or {...}

-- Lua 5.1 / 5.2+ compatibility
local unpack = unpack or table.unpack

-- All sides
local SIDES = {"top","bottom","left","right","front","back"}

local function errExit(msg)
    io.stderr:write("monitor-app: " .. msg .. "\n")
    return 1
end

local function colorPrint(c, s)
    if term.isColor() then term.setTextColor(c) end
    print(s)
    if term.isColor() then term.setTextColor(colors.white) end
end

-- Discover all attached monitors (side -> wrap)
local function discoverMonitors()
    local out = {}
    for _, side in ipairs(SIDES) do
        if peripheral.isPresent(side) and peripheral.getType(side) == "monitor" then
            out[side] = peripheral.wrap(side)
        end
    end
    return out
end

-- Try Drivers.Monitor first, fall back to direct scan
local function listMonitors()
    if _G.Drivers and _G.Drivers.monitor and _G.Drivers.monitor.list then
        local list = _G.Drivers.monitor.list()
        if list and #list > 0 then return list end
    end
    -- fallback: scan directly
    local out = {}
    for side, wrap in pairs(discoverMonitors()) do
        local w, h = wrap.getSize()
        local adv = wrap.isColor and wrap.isColor() or false
        table.insert(out, {
            side = side, wrap = wrap, width = w, height = h, advanced = adv
        })
    end
    table.sort(out, function(a, b) return a.side < b.side end)
    return out
end

---------------------------------------------------------------- subcommands ---

local function cmdList()
    local monitors = listMonitors()
    if #monitors == 0 then
        print("(no monitors attached)")
        return 0
    end
    print(string.format("%-8s %-8s %-12s %s",
        "SIDE", "SIZE", "TYPE", "DRIVER"))
    for _, m in ipairs(monitors) do
        local sizeStr = tostring(m.width) .. "x" .. tostring(m.height)
        local advStr = m.advanced and "color" or "mono"
        print(string.format("%-8s %-8s %-12s %s",
            m.side, sizeStr, advStr, "monitor"))
    end
    print("")
    print(string.format("%d monitor(s) attached.", #monitors))
    return 0
end

local function cmdAttach(side)
    if not side then return errExit("usage: monitor-app attach <side>") end
    if not peripheral.isPresent(side) then
        return errExit("no peripheral at " .. side)
    end
    if peripheral.getType(side) ~= "monitor" then
        return errExit(side .. " is not a monitor (got: " .. tostring(peripheral.getType(side)) .. ")")
    end
    local wrap = peripheral.wrap(side)
    local w, h = wrap.getSize()
    local adv = wrap.isColor and wrap.isColor() or false
    print(string.format("Monitor at %-8s", side))
    print(string.format("  Size      : %dx%d", w, h))
    print(string.format("  Type      : %s", adv and "color" or "mono"))
    print(string.format("  Cursor    : %s", tostring(wrap.getCursorPos and wrap.getCursorPos() or "?")))
    print(string.format("  Blink     : %s", tostring(wrap.getCursorBlink and wrap.getCursorBlink() or "?")))
    if wrap.getTextScale then
        print(string.format("  Text scale: %s", tostring(wrap.getTextScale())))
    end
    return 0
end

local function cmdDisplay(side, ...)
    if not side then return errExit("usage: monitor-app display <side> <text>") end
    local text = table.concat({...}, " ")
    if not peripheral.isPresent(side) then
        return errExit("no peripheral at " .. side)
    end
    if peripheral.getType(side) ~= "monitor" then
        return errExit(side .. " is not a monitor")
    end
    local wrap = peripheral.wrap(side)
    -- write at current cursor; if cursor at origin, also clear first
    local x, y = wrap.getCursorPos()
    if x == 1 and y == 1 then wrap.clear() end
    wrap.write(text)
    -- advance cursor to next line
    local _, h = wrap.getSize()
    y = y + 1
    if y > h then y = h; wrap.scroll(1) end
    wrap.setCursorPos(1, y)
    return 0
end

local function cmdClear(side)
    if not side then return errExit("usage: monitor-app clear <side>") end
    if not peripheral.isPresent(side) then
        return errExit("no peripheral at " .. side)
    end
    if peripheral.getType(side) ~= "monitor" then
        return errExit(side .. " is not a monitor")
    end
    local wrap = peripheral.wrap(side)
    wrap.clear()
    wrap.setCursorPos(1, 1)
    return 0
end

local function cmdResize(side, wStr, hStr)
    if not side then return errExit("usage: monitor-app resize <side> <scale1-5>") end
    if not peripheral.isPresent(side) then
        return errExit("no peripheral at " .. side)
    end
    if peripheral.getType(side) ~= "monitor" then
        return errExit(side .. " is not a monitor")
    end
    local wrap = peripheral.wrap(side)
    if not wrap.setTextScale then
        return errExit("monitor does not support setTextScale")
    end
    -- Accept either a single scale (1-5) or <w> <h>; we use the first arg
    -- as the text scale, ignoring the second for API compatibility.
    local scale = tonumber(wStr)
    if not scale then
        -- try parsing as "5x3" form
        scale = tonumber(wStr:match("^(%d+)"))
    end
    if not scale or scale < 1 or scale > 5 then
        return errExit("invalid scale (must be 1-5); got: " .. tostring(wStr))
    end
    wrap.setTextScale(scale)
    local w, h = wrap.getSize()
    print(string.format("Set %s text scale to %d  ->  new size: %dx%d", side, scale, w, h))
    return 0
end

-- redirect: switch term output to monitor, then exec /bin/sh.lua
local function cmdRedirect(side)
    if not side then return errExit("usage: monitor-app redirect <side>") end
    if not peripheral.isPresent(side) then
        return errExit("no peripheral at " .. side)
    end
    if peripheral.getType(side) ~= "monitor" then
        return errExit(side .. " is not a monitor")
    end
    local wrap = peripheral.wrap(side)
    wrap.clear()
    wrap.setCursorPos(1, 1)

    -- Redirect term to the monitor
    local oldTerm = term.redirect(wrap)

    -- Exec the shell on this monitor
    local shellPath = "/bin/sh.lua"
    if not fs.exists(shellPath) then
        term.redirect(oldTerm)
        return errExit("shell not found at " .. shellPath)
    end

    local pid
    if _G.Kernel and _G.Kernel.exec then
        pid = _G.Kernel.exec(shellPath, {})
        if pid and _G.Kernel.wait then
            _G.Kernel.wait(pid)
        end
    else
        -- Fall back to dofile
        local fn, err = loadfile(shellPath)
        if not fn then
            term.redirect(oldTerm)
            return errExit("cannot load shell: " .. tostring(err))
        end
        pcall(fn)
    end

    -- Restore the original term
    term.redirect(oldTerm)
    return 0
end

-- mirror: copy the main terminal's contents to every attached monitor
local function cmdMirror()
    local monitors = listMonitors()
    if #monitors == 0 then
        return errExit("no monitors attached")
    end
    print("Mirroring main terminal to " .. #monitors .. " monitor(s).")
    print("Press Ctrl+C to stop.")
    print("")

    -- Capture the original term so we can read from it
    local mainW, mainH = term.getSize()

    -- We'll periodically snapshot the main screen and replicate.
    -- CC:T has no direct screen-read API, but we can use term.redirect
    -- to a multi-target redirect object.
    local MultiTarget = {}
    MultiTarget.__index = MultiTarget

    function MultiTarget.new(targets)
        local self = setmetatable({}, MultiTarget)
        self.targets = targets  -- list of redirect objects
        self.main = targets[1]
        return self
    end
    -- Forward every term method to all targets
    for _, name in ipairs({"write","scroll","setCursorPos","setCursorBlink",
        "setTextColor","setBackgroundColor","clear","clearLine"}) do
        MultiTarget[name] = function(self, ...)
            for _, t in ipairs(self.targets) do
                if t[name] then pcall(t[name], t, ...) end
            end
        end
    end
    -- getSize/getCursorPos/getTextColor/getBackgroundColor come from main
    for _, name in ipairs({"getSize","getCursorPos","getTextColor","getBackgroundColor","isColor"}) do
        MultiTarget[name] = function(self, ...)
            if self.main and self.main[name] then return self.main[name](self.main, ...) end
            return nil
        end
    end

    -- Build redirect objects: main term (current) + all monitor wraps
    local targets = {}
    -- Capture current term as a redirect
    local curTerm = term.current and term.current() or term
    table.insert(targets, curTerm)
    for _, m in ipairs(monitors) do
        -- clear each monitor first
        m.wrap.clear()
        m.wrap.setCursorPos(1, 1)
        table.insert(targets, m.wrap)
    end

    local multi = MultiTarget.new(targets)
    local oldTerm = term.redirect(multi)

    -- Run the shell on the multi-target
    local shellPath = "/bin/sh.lua"
    local fn, err = loadfile(shellPath)
    if not fn then
        term.redirect(oldTerm)
        return errExit("cannot load shell: " .. tostring(err))
    end
    local ok, rerr = pcall(fn)

    -- Restore
    term.redirect(oldTerm)
    if not ok then
        io.stderr:write("monitor-app: shell error: " .. tostring(rerr) .. "\n")
        return 1
    end
    return 0
end

---------------------------------------------------------------- usage ---

local function printUsage()
    print([[Usage: monitor-app <command> [args]

Commands:
  (no args)                 List attached monitors
  attach <side>             Show status of monitor at <side>
  display <side> <text>     Write text to a monitor
  clear <side>             Clear a monitor
  redirect <side>           Run /bin/sh.lua on a monitor
  resize <side> <scale>    Set text scale (1-5)
  mirror                    Mirror main terminal to all monitors]])
end

---------------------------------------------------------------- main ---

local function main()
    local cmd = args[1]
    if not cmd then
        -- Default to listing when no args provided
        return cmdList()
    end
    if cmd == "-h" or cmd == "--help" or cmd == "help" then
        printUsage()
        return 0
    end

    if cmd == "list" or cmd == "ls" then
        return cmdList()
    elseif cmd == "attach" or cmd == "status" then
        return cmdAttach(args[2])
    elseif cmd == "display" or cmd == "write" then
        return cmdDisplay(args[2], unpack(args, 3))
    elseif cmd == "clear" or cmd == "cls" then
        return cmdClear(args[2])
    elseif cmd == "redirect" or cmd == "run" then
        return cmdRedirect(args[2])
    elseif cmd == "resize" or cmd == "scale" then
        return cmdResize(args[2], args[3], args[4])
    elseif cmd == "mirror" then
        return cmdMirror()
    else
        io.stderr:write("monitor-app: unknown command '" .. cmd .. "'\n")
        printUsage()
        return 1
    end
end

return main()
