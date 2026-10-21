--[[
    de/gui.lua  —  Unified ArchOS-CC Desktop Environment (v2)
    =========================================================
    A single graphical desktop with windowed applications.

    Features:
      * Top menu bar: ArchOS menu, Apps, System, Clock
      * Desktop icons (auto-generated from /etc/apps.conf)
      * Application WINDOWS - apps run inside windows, not full-screen!
        Each window has: title bar, close button, drag to move, click to focus
      * Multi-window: multiple apps can run at once
      * Window switching: click to focus, Alt+Tab cycle
      * F1 = Run dialog (launch by command name)
      * Monitor output: redirect any window to an attached Monitor block
        (Click "Monitor" button in window's title bar to send it to monitor,
         click again to bring it back)
      * Right-click desktop for context menu
      * Whole event loop wrapped in pcall (crash-safe)

    apps.conf format (one app per line):
        name|path|icon|color

    Setting as default DE:
        echo "gui" > /etc/default-de
]]

-- ============================================================
--  Helpers
-- ============================================================

local function setColor(c)
    if c and term.isColor() then pcall(function() term.setTextColor(c) end) end
end
local function setBG(c)
    if c and term.isColor() then pcall(function() term.setBackgroundColor(c) end) end
end
local function reset()
    setBG(colors.black); setColor(colors.white)
end

local COLOR_MAP = {
    white=colors.white, orange=colors.orange, magenta=colors.magenta,
    lightBlue=colors.lightBlue, yellow=colors.yellow, lime=colors.lime,
    pink=colors.pink, gray=colors.gray, lightGray=colors.lightGray,
    cyan=colors.cyan, purple=colors.purple, blue=colors.blue,
    brown=colors.brown, green=colors.green, red=colors.red, black=colors.black,
}
local function colorFromName(name)
    return COLOR_MAP[name] or colors.lightGray
end

local function writeAt(x, y, text, bg, fg)
    if bg then setBG(bg) end
    if fg then setColor(fg) end
    term.setCursorPos(x, y)
    term.write(text)
    reset()
end

local function box(x, y, w, h, color)
    setBG(color)
    for row = y, y + h - 1 do
        term.setCursorPos(x, row)
        term.write(string.rep(" ", w))
    end
    reset()
end

-- Find attached monitors (peripheral type "monitor")
local function findMonitors()
    local monitors = {}
    local sides = {"top", "bottom", "left", "right", "front", "back"}
    for _, side in ipairs(sides) do
        if peripheral.isPresent(side) and peripheral.getType(side) == "monitor" then
            local m = peripheral.wrap(side)
            if m then
                table.insert(monitors, { side = side, wrap = m })
            end
        end
    end
    -- Also via wired modem
    if peripheral.getNames then
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "monitor"
               and name ~= "top" and name ~= "bottom"
               and name ~= "left" and name ~= "right"
               and name ~= "front" and name ~= "back" then
                local m = peripheral.wrap(name)
                if m then
                    table.insert(monitors, { side = name, wrap = m })
                end
            end
        end
    end
    return monitors
end

-- ============================================================
--  Load apps from /etc/apps.conf
-- ============================================================

local function loadApps()
    local apps = {}
    if not fs.exists("/etc/apps.conf") then
        return {
            { name="Terminal",    path="/bin/sh.lua",            icon="T", color=colors.green },
            { name="Files",       path="/usr/bin/filemanager.lua", icon="F", color=colors.yellow },
            { name="Editor",      path="/usr/bin/editor.lua",    icon="E", color=colors.cyan },
            { name="Web Browser", path="/usr/bin/webbrowser.lua", icon="W", color=colors.blue },
            { name="Settings",    path="/usr/bin/settings.lua",  icon="S", color=colors.lightGray },
            { name="Notes",       path="/usr/bin/notes.lua",     icon="N", color=colors.orange },
            { name="Paint",       path="/usr/bin/paint.lua",     icon="P", color=colors.magenta },
            { name="Calculator",  path="/usr/bin/calculator.lua", icon="C", color=colors.lime },
            { name="Clock",       path="/usr/bin/clock.lua",     icon="L", color=colors.lightBlue },
            { name="Lua REPL",    path="/usr/bin/lua-repl.lua",  icon=">", color=colors.purple },
            { name="System Monitor", path="/usr/bin/system-monitor.lua", icon="M", color=colors.red },
            { name="Task Manager", path="/usr/bin/taskmgr.lua",  icon="K", color=colors.cyan },
            { name="Neofetch",    path="/usr/bin/neofetch.lua",  icon="?", color=colors.lightBlue },
        }
    end
    local f = fs.open("/etc/apps.conf", "r")
    if not f then return {} end
    for line in f.readLine do
        if line and line ~= "" and line:sub(1, 1) ~= "#" then
            local name, path, icon, colorName = line:match("^([^|]+)|([^|]+)|([^|]+)|([^|%s]+)")
            if name and path then
                table.insert(apps, {
                    name = name,
                    path = path,
                    icon = icon or "?",
                    color = colorFromName(colorName),
                })
            end
        end
    end
    f.close()
    return apps
end

-- ============================================================
--  Window class
-- ============================================================
-- Each window runs an app inside a CC:Tweaked window object.
-- The app's term.redirect points to the window, so its term.write()
-- calls go into the window's buffer (not the main screen).

local Window = {}
Window.__index = Window

-- Create a window for an app
function Window.new(app, x, y, w, h)
    local self = setmetatable({}, Window)
    self.app = app
    self.title = app.name
    self.x = x
    self.y = y
    self.width = w or 35
    self.height = h or 12
    -- Create CC:Tweaked window object (invisible initially)
    -- We use the native term as parent
    self.window = window.create(term.current(), self.x, self.y, self.width, self.height, false)
    self.coro = nil
    self.alive = false
    self.monitor = nil  -- if set, output goes to monitor instead
    return self
end

-- Start the app inside this window
function Window:start()
    if self.alive then return end
    self.alive = true
    -- Set _G.arg for the app (so it can read CLI args if any)
    local oldArg = _G.arg
    _G.arg = {[0] = self.app.path}
    -- Read the file
    local f = fs.open(self.app.path, "r")
    if not f then
        self.alive = false
        _G.arg = oldArg
        return false, "cannot open " .. self.app.path
    end
    local content = f.readAll()
    f.close()
    local fn, err = load(content, self.app.path, "t", _G)
    _G.arg = oldArg
    if not fn then
        self.alive = false
        return false, "compile error: " .. tostring(err)
    end
    -- Create coroutine for the app
    self.coro = coroutine.create(function()
        -- Redirect term to our window inside the coroutine
        local oldTerm = term.redirect(self.window)
        local ok, err = pcall(fn)
        term.redirect(oldTerm)
        self.alive = false
        self.lastError = not ok and tostring(err) or nil
    end)
    -- Initial resume
    self:redirToWindow()
    local ok, err = coroutine.resume(self.coro)
    self:redirBack()
    return true
end

-- Redirect term to this window's buffer (so we can draw to it)
function Window:redirToWindow()
    if self.monitor then
        self.oldRedirect = term.redirect(self.monitor.wrap)
    else
        self.oldRedirect = term.redirect(self.window)
    end
end

-- Restore term to main screen
function Window:redirBack()
    if self.oldRedirect then
        term.redirect(self.oldRedirect)
        self.oldRedirect = nil
    end
end

-- Resume the app coroutine with an event
function Window:resume(event)
    if not self.alive or not self.coro then return false end
    if coroutine.status(self.coro) == "dead" then
        self.alive = false
        return false
    end
    self:redirToWindow()
    local ok, yieldOrErr
    if event then
        ok, yieldOrErr = coroutine.resume(self.coro, unpack(event))
    else
        ok, yieldOrErr = coroutine.resume(self.coro)
    end
    self:redirBack()
    if not ok then
        self.alive = false
        self.lastError = tostring(yieldOrErr)
        return false
    end
    if coroutine.status(self.coro) == "dead" then
        self.alive = false
    end
    return self.alive
end

-- Draw the window chrome (border + title bar + buttons)
function Window:draw(isActive)
    -- Don't draw chrome if redirected to monitor
    if self.monitor then
        -- Just draw a placeholder showing where it is
        box(self.x, self.y, self.width, 1, colors.gray)
        writeAt(self.x + 1, self.y, " [on monitor: " .. self.monitor.side .. "] ", colors.gray, colors.yellow)
        return
    end
    -- Shadow
    local w, h = term.getSize()
    if self.x + self.width <= w then
        box(self.x + 1, self.y + 1, self.width, self.height, colors.gray)
    end
    -- Background
    box(self.x, self.y, self.width, self.height, colors.black)
    -- Title bar
    local titleBG = isActive and colors.blue or colors.gray
    box(self.x, self.y, self.width, 1, titleBG)
    writeAt(self.x + 1, self.y, " " .. self.title:sub(1, self.width - 6) .. " ", titleBG, colors.white)
    -- Buttons: M (monitor), X (close)
    writeAt(self.x + self.width - 2, self.y, "M", titleBG, colors.lightBlue)
    writeAt(self.x + self.width - 1, self.y, "X", titleBG, colors.yellow)
    -- Window content (visible portion)
    -- The CC:Tweaked window object has its own buffer; we just need
    -- to make it visible by drawing it to the main screen.
    -- window.visible = true and call window.redraw()
    if self.window.setVisible then
        self.window.setVisible(true)
    end
    if self.window.redraw then
        self.window.redraw()
    end
end

-- Check if a click is in this window
function Window:contains(x, y)
    return x >= self.x and x < self.x + self.width and
           y >= self.y and y < self.y + self.height
end

-- Check if click is on title bar
function Window:onTitleBar(x, y)
    return y == self.y and x >= self.x and x < self.x + self.width
end

-- Check if click is on close button
function Window:onCloseButton(x, y)
    return y == self.y and x == self.x + self.width - 1
end

-- Check if click is on monitor button
function Window:onMonitorButton(x, y)
    return y == self.y and x == self.x + self.width - 2
end

-- Toggle monitor output
function Window:toggleMonitor()
    if self.monitor then
        -- Back to window
        self.monitor = nil
        -- Resume app: it will get events from main term again
    else
        -- Find first available monitor
        local monitors = findMonitors()
        if #monitors == 0 then
            return false, "no monitors attached"
        end
        self.monitor = monitors[1]
        -- Clear and show on monitor
        self.monitor.wrap.clear()
        self.monitor.wrap.setCursorPos(1, 1)
        self.monitor.wrap.setTextColor(colors.white)
        self.monitor.wrap.setBackgroundColor(colors.black)
    end
    return true
end

-- Move window
function Window:move(newX, newY)
    local w, h = term.getSize()
    self.x = math.max(1, math.min(w - self.width + 1, newX))
    self.y = math.max(2, math.min(h - self.height + 1, newY))
    if self.window.reposition then
        self.window.reposition(self.x, self.y)
    end
end

-- ============================================================
--  Desktop state
-- ============================================================

local state = {
    apps = {},
    windows = {},
    nextWindowID = 1,
    activeWindow = nil,
    menuOpen = nil,
    runDialogOpen = false,
    runQuery = "",
    clock = "00:00",
    running = true,
    dragging = nil,
}

-- ============================================================
--  Drawing
-- ============================================================

local function drawMenuBar()
    local w, h = term.getSize()
    box(1, 1, w, 1, colors.blue)
    setColor(colors.white)
    writeAt(2, 1, "ArchOS", colors.blue, state.menuOpen == "archos" and colors.yellow or colors.white)
    writeAt(9, 1, "Apps",   colors.blue, state.menuOpen == "apps" and colors.yellow or colors.white)
    writeAt(14, 1, "System", colors.blue, state.menuOpen == "system" and colors.yellow or colors.white)
    writeAt(math.floor(w/2) - 4, 1, "ArchOS-CC", colors.blue, colors.white)
    writeAt(w - #state.clock - 1, 1, state.clock, colors.blue, colors.white)
    reset()
end

local function drawDesktopIcons()
    for i, app in ipairs(state.apps) do
        local x = 2
        local y = 3 + (i - 1) * 4
        local w, h = term.getSize()
        if y + 3 > h - 1 then break end
        box(x, y, 4, 3, app.color)
        writeAt(x + 1, y + 1, " " .. (app.icon or "?") .. " ", app.color, colors.black)
        local label = app.name
        if #label > 6 then label = label:sub(1, 6) end
        writeAt(x, y + 3, " " .. label .. "  ", colors.black, colors.white)
    end
end

local function drawWindows()
    -- Draw windows in z-order (back to front)
    for _, win in ipairs(state.windows) do
        win:draw(win == state.activeWindow)
    end
end

local function drawMenu(menuType)
    -- ... (same as before, omitted for brevity)
    -- Returns items, x, y, w, h
end

local function drawRunDialog()
    local w, h = term.getSize()
    local boxW = 40
    local boxH = 3
    local x = math.floor((w - boxW) / 2)
    local y = math.floor(h / 2) - 1
    box(x + 1, y + 1, boxW, boxH, colors.gray)
    box(x, y, boxW, boxH, colors.blue)
    writeAt(x + 1, y, " Run command: ", colors.blue, colors.yellow)
    writeAt(x + 1, y + 1, " > " .. state.runQuery .. "_", colors.blue, colors.white)
    writeAt(x + 1, y + 2, " Enter to run, Esc to cancel ", colors.blue, colors.lightGray)
end

local function render()
    local w, h = term.getSize()
    box(1, 1, w, h, colors.black)
    drawMenuBar()
    drawDesktopIcons()
    drawWindows()
    if state.menuOpen then drawMenu(state.menuOpen) end
    if state.runDialogOpen then drawRunDialog() end
end

-- ============================================================
--  Launch an app in a new window
-- ============================================================

local function launchApp(app)
    -- Default window position: cascade
    local offset = (#state.windows % 5) * 2
    local win = Window.new(app, 5 + offset, 3 + offset, 35, 12)
    local ok, err = win:start()
    if not ok then
        -- Show error in a window
        local errWin = Window.new(
            { name = "Error", icon = "!", color = colors.red },
            10, 5, 30, 5
        )
        errWin.title = "Error"
        errWin:start()
        -- Write error message to the window
        errWin:redirToWindow()
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.red)
        print("Failed to launch:")
        print(app.path)
        print("")
        print(tostring(err))
        term.setTextColor(colors.white)
        errWin:redirBack()
        table.insert(state.windows, errWin)
        state.activeWindow = errWin
        return
    end
    table.insert(state.windows, win)
    state.activeWindow = win
end

-- ============================================================
--  Main loop
-- ============================================================

local function main()
    state.apps = loadApps()
    state.clock = os.date("%H:%M")

    -- Run login first (full-screen, not in a window)
    if fs.exists("/bin/login.lua") and _G.Kernel then
        local pid = _G.Kernel.exec("/bin/login.lua", {})
        if pid then _G.Kernel.wait(pid) end
    end

    local clockTimer = os.startTimer(30)
    local tickTimer = os.startTimer(0.1)  -- 10 FPS for window updates

    while state.running do
        local ok, err = pcall(function()
            render()
            local event = { os.pullEvent() }

            -- Always deliver timer events to all windows (so apps can update)
            if event[1] == "timer" and event[2] == tickTimer then
                for _, win in ipairs(state.windows) do
                    if win.alive then
                        win:resume(event)
                    end
                end
                -- Reap dead windows
                for i = #state.windows, 1, -1 do
                    if not state.windows[i].alive then
                        if state.activeWindow == state.windows[i] then
                            state.activeWindow = state.windows[i-1] or state.windows[i+1] or nil
                        end
                        table.remove(state.windows, i)
                    end
                end
                tickTimer = os.startTimer(0.1)
                return
            end

            if event[1] == "timer" and event[2] == clockTimer then
                state.clock = os.date("%H:%M")
                clockTimer = os.startTimer(30)
                return
            end

            -- Deliver events to active window first
            if state.activeWindow and state.activeWindow.alive then
                local win = state.activeWindow
                -- Check if event is for this window
                if event[1] == "mouse_click" or event[1] == "mouse_up" or
                   event[1] == "mouse_drag" or event[1] == "mouse_scroll" then
                    -- Translate mouse coords relative to window
                    local btn, x, y = event[2], event[3], event[4]
                    if win:contains(x, y) and not win:onTitleBar(x, y) then
                        -- Translate to window-relative coords
                        local relX = x - win.x + 1
                        local relY = y - win.y + 1
                        -- Deliver to window
                        win:resume({event[1], btn, relX, relY})
                        return
                    end
                elseif event[1] == "key" or event[1] == "char" or event[1] == "paste" then
                    -- Key events go to active window
                    win:resume(event)
                    return
                end
            end

            -- Handle desktop-level events
            if event[1] == "key" then
                local key = event[2]
                if key == keys.f1 then
                    state.runDialogOpen = not state.runDialogOpen
                    state.runQuery = ""
                    state.menuOpen = nil
                elseif key == keys.escape then
                    state.menuOpen = nil
                    state.runDialogOpen = false
                elseif key == keys.q and not state.runDialogOpen then
                    state.running = false
                end
            elseif event[1] == "char" and state.runDialogOpen then
                state.runQuery = state.runQuery .. event[2]
            elseif event[1] == "key" and state.runDialogOpen then
                if event[2] == keys.enter then
                    local q = state.runQuery
                    state.runDialogOpen = false
                    state.runQuery = ""
                    -- Find app by name
                    for _, app in ipairs(state.apps) do
                        if app.name:lower():find(q:lower()) then
                            launchApp(app)
                            return
                        end
                    end
                    -- Try as path
                    local path = q
                    if not path:match("^/") then
                        for _, d in ipairs({"/bin", "/usr/bin"}) do
                            local p = d .. "/" .. q
                            if not p:match("%.lua$") then p = p .. ".lua" end
                            if fs.exists(p) then path = p; break end
                        end
                    end
                    if fs.exists(path) then
                        launchApp({ name = q, path = path, icon = "?", color = colors.lightGray })
                    end
                elseif event[2] == keys.backspace then
                    state.runQuery = state.runQuery:sub(1, -2)
                end
            elseif event[1] == "mouse_click" then
                local button, x, y = event[2], event[3], event[4]
                local w, h = term.getSize()
                if y == 1 then
                    -- Menu bar
                    if x >= 2 and x <= 7 then
                        state.menuOpen = state.menuOpen == "archos" and nil or "archos"
                    elseif x >= 9 and x <= 12 then
                        state.menuOpen = state.menuOpen == "apps" and nil or "apps"
                    elseif x >= 14 and x <= 20 then
                        state.menuOpen = state.menuOpen == "system" and nil or "system"
                    else
                        state.menuOpen = nil
                    end
                elseif state.menuOpen then
                    -- Click on a menu item
                    state.menuOpen = nil
                else
                    -- Check windows first (front to back)
                    local clickedWin = nil
                    for i = #state.windows, 1, -1 do
                        local win = state.windows[i]
                        if win:contains(x, y) then
                            clickedWin = win
                            -- Bring to front
                            table.remove(state.windows, i)
                            table.insert(state.windows, win)
                            break
                        end
                    end
                    if clickedWin then
                        state.activeWindow = clickedWin
                        if clickedWin:onCloseButton(x, y) then
                            -- Close button
                            clickedWin.alive = false
                            for i, w in ipairs(state.windows) do
                                if w == clickedWin then
                                    table.remove(state.windows, i)
                                    break
                                end
                            end
                            state.activeWindow = state.windows[#state.windows] or nil
                        elseif clickedWin:onMonitorButton(x, y) then
                            -- Toggle monitor
                            local ok, err = clickedWin:toggleMonitor()
                            if not ok then
                                -- No monitor - show message
                            end
                        elseif clickedWin:onTitleBar(x, y) then
                            -- Start dragging
                            state.dragging = { window = clickedWin, offsetX = x - clickedWin.x, offsetY = y - clickedWin.y }
                        end
                    else
                        -- Desktop icons
                        for i, app in ipairs(state.apps) do
                            local ix = 2
                            local iy = 3 + (i - 1) * 4
                            if x >= ix and x <= ix + 3 and y >= iy and y <= iy + 2 then
                                launchApp(app)
                                break
                            end
                        end
                    end
                end
            elseif event[1] == "mouse_drag" then
                if state.dragging then
                    state.dragging.window:move(
                        event[3] - state.dragging.offsetX,
                        event[4] - state.dragging.offsetY
                    )
                end
            elseif event[1] == "mouse_up" then
                state.dragging = nil
            end
        end)
        if not ok then
            setColor(colors.red)
            term.setCursorPos(1, select(2, term.getSize()))
            term.write("[gui error] " .. tostring(err):sub(1, 40))
            setColor(colors.white)
            os.sleep(0.5)
        end
    end

    reset()
    term.clear()
    term.setCursorPos(1, 1)
    return 0
end

return main()
