--[[
    de/gui.lua  —  Unified ArchOS-CC Desktop Environment (v4)
    ==========================================================
    GUI launches FIRST (no text login), with built-in graphical login.
    Apps run in windows with VISIBLE colored borders.
    Keyboard events (Enter, etc.) properly delivered to windows.

    Features:
      * Graphical login screen (no text mode)
      * Colored window borders (visible!)
      * Title bar: [_]min  [□]max  [X]close
      * Drag title bar = move, drag corner = resize
      * Taskbar at bottom for minimized apps
      * Desktop icons from /etc/apps.conf
      * F1 = Run dialog
      * Full mouse + keyboard support
      * Crash-safe (pcall on every event)
]]

-- Window border colors (cycle for each new window)
local BORDER_COLORS = {
    colors.lightBlue, colors.green, colors.orange, colors.magenta,
    colors.cyan, colors.pink, colors.lime, colors.purple,
}
local nextColorIdx = 1

local function setColor(c)
    if c and term.isColor() then pcall(function() term.setTextColor(c) end) end
end
local function setBG(c)
    if c and term.isColor() then pcall(function() term.setBackgroundColor(c) end) end
end
local function reset() setBG(colors.black); setColor(colors.white) end

local COLOR_MAP = {
    white=colors.white, orange=colors.orange, magenta=colors.magenta,
    lightBlue=colors.lightBlue, yellow=colors.yellow, lime=colors.lime,
    pink=colors.pink, gray=colors.gray, lightGray=colors.lightGray,
    cyan=colors.cyan, purple=colors.purple, blue=colors.blue,
    brown=colors.brown, green=colors.green, red=colors.red, black=colors.black,
}
local function colorFromName(n) return COLOR_MAP[n] or colors.lightGray end

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

local function loadApps()
    local apps = {}
    if not fs.exists("/etc/apps.conf") then
        return {
            {name="Terminal", path="/bin/sh.lua", icon="T", color=colors.green},
            {name="Files", path="/usr/bin/filemanager.lua", icon="F", color=colors.yellow},
            {name="Editor", path="/usr/bin/editor.lua", icon="E", color=colors.cyan},
            {name="Web", path="/usr/bin/webbrowser.lua", icon="W", color=colors.blue},
        }
    end
    local f = fs.open("/etc/apps.conf", "r")
    if not f then return {} end
    for line in f.readLine do
        if line and line ~= "" and line:sub(1,1) ~= "#" then
            local name, path, icon, colorName = line:match("^([^|]+)|([^|]+)|([^|]+)|([^|%s]+)")
            if name and path then
                table.insert(apps, {name=name, path=path, icon=icon or "?", color=colorFromName(colorName)})
            end
        end
    end
    f.close()
    return apps
end

-- ============================================================
--  Window class — runs an app inside a bordered window
-- ============================================================
-- The window object is created SMALLER than the visual window,
-- leaving room for the border (1 char on each side, 1 for title bar,
-- 1 for bottom border). The app writes into the inner area.

local Window = {}
Window.__index = Window

function Window.new(app, x, y, w, h)
    local self = setmetatable({}, Window)
    self.app = app
    self.title = app.name
    self.x = x or 5
    self.y = y or 3
    self.width = w or 35       -- total width including borders
    self.height = h or 12     -- total height including borders
    self.borderColor = BORDER_COLORS[nextColorIdx]
    nextColorIdx = nextColorIdx % #BORDER_COLORS + 1
    self.minimized = false
    self.maximized = false
    self.savedX = self.x
    self.savedY = self.y
    self.savedW = self.width
    self.savedH = self.height
    -- Inner window (where app content goes): offset by 1 for left border,
    -- 1 for title bar. Width = total - 2 (left+right borders).
    -- Height = total - 3 (title bar + bottom border + content padding).
    local innerX = self.x + 1
    local innerY = self.y + 1
    local innerW = self.width - 2
    local innerH = self.height - 2
    self.window = window.create(term.current(), innerX, innerY, innerW, innerH, false)
    self.coro = nil
    self.alive = false
    self.lastError = nil
    return self
end

function Window:start()
    if self.alive then return true end
    self.alive = true
    local oldArg = _G.arg
    _G.arg = {[0] = self.app.path}
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
    self.coro = coroutine.create(function()
        local oldTerm = term.redirect(self.window)
        local ok, err = pcall(fn)
        term.redirect(oldTerm)
        self.alive = false
        if not ok then self.lastError = tostring(err) end
    end)
    self:_resume()
    return true
end

function Window:_resume(event)
    if not self.alive or not self.coro then return end
    if coroutine.status(self.coro) == "dead" then
        self.alive = false
        return
    end
    local oldRedirect = term.redirect(self.window)
    if event then
        coroutine.resume(self.coro, unpack(event))
    else
        coroutine.resume(self.coro)
    end
    term.redirect(oldRedirect)
    if coroutine.status(self.coro) == "dead" then
        self.alive = false
    end
end

-- Resume with a mouse event, translating to inner window coords
function Window:resumeMouse(eventType, btn, x, y)
    if not self.alive then return end
    -- Translate to inner window coordinates
    local relX = x - self.x  -- -1 for left border → 0-based → +1 for inner
    local relY = y - self.y - 1  -- -1 for title bar
    -- Clamp check: only deliver if inside inner area
    if relX < 1 or relX > self.width - 2 then return end
    if relY < 1 or relY > self.height - 2 then return end
    self:_resume({eventType, btn, relX, relY})
end

-- Resume with a keyboard event (key/char/paste)
function Window:resumeKey(...)
    if not self.alive then return end
    self:_resume({...})
end

function Window:drawChrome(isActive)
    -- Draw the visible border and title bar AROUND the window content.
    -- The CC:T window object handles its own content; we draw chrome
    -- on the MAIN screen (after redirecting back).

    -- Title bar
    local tb = isActive and self.borderColor or colors.gray
    box(self.x, self.y, self.width, 1, tb)
    local titleText = self.title:sub(1, self.width - 8)
    writeAt(self.x + 1, self.y, " " .. titleText .. " ", tb, colors.white)
    -- Buttons in title bar
    local btnX = self.x + self.width - 5
    writeAt(btnX, self.y, "_", tb, colors.yellow)         -- minimize
    writeAt(btnX + 1, self.y, "[]", tb, colors.lightBlue)  -- maximize
    writeAt(btnX + 3, self.y, "X", tb, colors.red)         -- close

    -- Left border
    setColor(self.borderColor)
    for row = self.y + 1, self.y + self.height - 2 do
        term.setCursorPos(self.x, row)
        term.write("|")
    end
    -- Right border
    for row = self.y + 1, self.y + self.height - 2 do
        term.setCursorPos(self.x + self.width - 1, row)
        term.write("|")
    end
    -- Bottom border with resize handle
    term.setCursorPos(self.x, self.y + self.height - 1)
    term.write("+" .. string.rep("-", self.width - 4) .. ">+")
    reset()
end

function Window:draw(isActive)
    if self.minimized then return end
    -- First, show the window content (the CC:T window object)
    if self.window.setVisible then self.window.setVisible(true) end
    if self.window.redraw then self.window.redraw() end
    -- THEN draw chrome ON TOP (borders, title bar, buttons)
    -- This ensures borders are visible and not covered by content.
    self:drawChrome(isActive)
end

function Window:contains(x, y)
    return x >= self.x and x < self.x + self.width and
           y >= self.y and y < self.y + self.height
end

-- Is point in the inner content area (not on borders)?
function Window:inContent(x, y)
    return x > self.x and x < self.x + self.width - 1 and
           y > self.y and y < self.y + self.height - 1
end

function Window:onTitleBar(x, y)
    return y == self.y and x >= self.x and x < self.x + self.width
end

function Window:onCloseButton(x, y)
    return y == self.y and x == self.x + self.width - 1
end

function Window:onMinButton(x, y)
    return y == self.y and x == self.x + self.width - 5
end

function Window:onMaxButton(x, y)
    return y == self.y and x >= self.x + self.width - 4 and x <= self.x + self.width - 2
end

function Window:onResizeHandle(x, y)
    return y == self.y + self.height - 1 and x == self.x + self.width - 2
end

function Window:close()
    self.alive = false
end

function Window:minimize()
    self.minimized = true
    if self.window.setVisible then self.window.setVisible(false) end
end

function Window:restore()
    self.minimized = false
end

function Window:toggleMaximize()
    if self.maximized then
        self.x = self.savedX
        self.y = self.savedY
        self.width = self.savedW
        self.height = self.savedH
        self.maximized = false
    else
        self.savedX = self.x
        self.savedY = self.y
        self.savedW = self.width
        self.savedH = self.height
        local w, h = term.getSize()
        self.x = 1
        self.y = 2
        self.width = w
        self.height = h - 2
        self.maximized = true
    end
    if self.window.reposition then
        self.window.reposition(self.x + 1, self.y + 1, self.width - 2, self.height - 2)
    end
end

function Window:move(newX, newY)
    local w, h = term.getSize()
    self.x = math.max(1, math.min(w - self.width + 1, newX))
    self.y = math.max(2, math.min(h - self.height, newY))
    if self.window.reposition then
        self.window.reposition(self.x + 1, self.y + 1)
    end
end

function Window:resize(newW, newH)
    self.width = math.max(10, newW)
    self.height = math.max(5, newH)
    if self.window.reposition then
        self.window.reposition(self.x + 1, self.y + 1, self.width - 2, self.height - 2)
    end
end

-- ============================================================
--  Graphical Login (built into GUI, no text mode)
-- ============================================================

local loginState = {
    loggedIn = false,
    username = "",
    password = "",
    field = "username",  -- "username" or "password"
    error = "",
}

local function drawLoginScreen()
    local w, h = term.getSize()
    box(1, 1, w, h, colors.black)
    -- Logo
    setColor(colors.lightBlue)
    term.setCursorPos(math.floor(w/2) - 12, math.floor(h/2) - 6)
    print("    ___               ____   ____  _  __")
    term.setCursorPos(math.floor(w/2) - 12, math.floor(h/2) - 5)
    print("   /   | ______ __ ___/  _/  / __ \\/ |/ /")
    term.setCursorPos(math.floor(w/2) - 12, math.floor(h/2) - 4)
    print("  / /| |/ __/ / // (_-< /    / /_/ /    /  ")
    term.setCursorPos(math.floor(w/2) - 12, math.floor(h/2) - 3)
    print(" /_/ |_|/_/  /_//_/___/___/  /____/_/|_/  ")
    setColor(colors.white)
    -- Login box
    local boxW = 30
    local boxH = 7
    local bx = math.floor((w - boxW) / 2)
    local by = math.floor(h/2) + 1
    box(bx, by, boxW, boxH, colors.blue)
    writeAt(bx + 1, by, " Login", colors.blue, colors.yellow)
    -- Username field
    local uLabel = "User: "
    local uValue = loginState.username
    if loginState.field == "username" then uValue = uValue .. "_" end
    writeAt(bx + 2, by + 2, uLabel .. uValue, colors.blue, colors.white)
    -- Password field (masked)
    local pLabel = "Pass: "
    local pValue = string.rep("*", #loginState.password)
    if loginState.field == "password" then pValue = pValue .. "_" end
    writeAt(bx + 2, by + 3, pLabel .. pValue, colors.blue, colors.white)
    -- Error message
    if loginState.error ~= "" then
        writeAt(bx + 2, by + 5, loginState.error, colors.blue, colors.red)
    else
        writeAt(bx + 2, by + 5, " Tab: switch field  Enter: login", colors.blue, colors.lightGray)
    end
    reset()
end

local function handleLoginEvent(event)
    if event[1] == "char" then
        if loginState.field == "username" then
            loginState.username = loginState.username .. event[2]
        else
            loginState.password = loginState.password .. event[2]
        end
        loginState.error = ""
    elseif event[1] == "key" then
        local key = event[2]
        if key == keys.tab then
            loginState.field = loginState.field == "username" and "password" or "username"
        elseif key == keys.enter then
            -- Try to authenticate
            local Users = _G.Users
            if Users then
                Users.load()
                local ok, err = Users.authenticate(loginState.username, loginState.password)
                if ok then
                    loginState.loggedIn = true
                    -- Set up environment
                    local user = Users.getUser(loginState.username) or {uid=0, gid=0, home="/root"}
                    if _G.Kernel then
                        _G.Kernel.setEnv("USER", loginState.username)
                        _G.Kernel.setEnv("HOME", user.home or "/root")
                        _G.Kernel.setEnv("SHELL", "/bin/sh.lua")
                        _G.Kernel.setEnv("PATH", "/bin:/sbin:/usr/bin:.")
                        local Process = _G.Process
                        if Process then
                            local cur = Process.current()
                            if cur then
                                cur.uid = user.uid
                                cur.gid = user.gid
                                cur.user = loginState.username
                            end
                        end
                    end
                    if _G.Kernel and user.home and fs.exists(user.home) then
                        _G.Kernel.setCwd(user.home)
                    end
                else
                    loginState.error = "Login incorrect"
                    loginState.password = ""
                    loginState.field = "username"
                end
            else
                loginState.error = "No user database"
            end
        elseif key == keys.backspace then
            if loginState.field == "username" then
                loginState.username = loginState.username:sub(1, -2)
            else
                loginState.password = loginState.password:sub(1, -2)
            end
        end
    end
end

-- ============================================================
--  Desktop state
-- ============================================================

local state = {
    apps = {},
    windows = {},
    activeWindow = nil,
    menuOpen = nil,
    menuItems = nil,
    menuX = 0,
    menuW = 0,
    runDialogOpen = false,
    runQuery = "",
    clock = "00:00",
    running = true,
    dragging = nil,
}

-- ============================================================
--  Drawing (desktop, menu, taskbar)
-- ============================================================

local function drawMenuBar()
    local w, h = term.getSize()
    box(1, 1, w, 1, colors.blue)
    writeAt(2, 1, "ArchOS", colors.blue, state.menuOpen=="archos" and colors.yellow or colors.white)
    writeAt(9, 1, "Apps", colors.blue, state.menuOpen=="apps" and colors.yellow or colors.white)
    writeAt(14, 1, "System", colors.blue, state.menuOpen=="system" and colors.yellow or colors.white)
    writeAt(math.floor(w/2)-4, 1, "ArchOS-CC", colors.blue, colors.white)
    writeAt(w-#state.clock-1, 1, state.clock, colors.blue, colors.white)
    reset()
end

local function drawDesktopIcons()
    for i, app in ipairs(state.apps) do
        local x = 2
        local y = 3 + (i-1)*4
        local _, h = term.getSize()
        if y + 3 > h - 2 then break end
        box(x, y, 4, 3, app.color)
        writeAt(x+1, y+1, " "..(app.icon or "?").." ", app.color, colors.black)
        local label = app.name
        if #label > 6 then label = label:sub(1,6) end
        writeAt(x, y+3, " "..label.."  ", colors.black, colors.white)
    end
end

local function drawTaskbar()
    local w, h = term.getSize()
    box(1, h, w, 1, colors.lightGray)
    setColor(colors.black)
    local x = 2
    for _, win in ipairs(state.windows) do
        if win.minimized then
            local label = win.title:sub(1, 12)
            local bw = #label + 4
            writeAt(x, h, " ["..label.."] ", colors.lightGray, colors.black)
            x = x + bw
        end
    end
    local openCount = 0
    for _, win in ipairs(state.windows) do
        if not win.minimized then openCount = openCount + 1 end
    end
    if openCount > 0 then
        writeAt(w - 15, h, " Open: " .. openCount .. " ", colors.lightGray, colors.black)
    end
    reset()
end

local function drawWindows()
    for _, win in ipairs(state.windows) do
        if not win.minimized then
            win:draw(win == state.activeWindow)
        end
    end
end

local function drawRunDialog()
    local w, h = term.getSize()
    local bw = 40
    local bh = 3
    local x = math.floor((w-bw)/2)
    local y = math.floor(h/2)-1
    box(x+1, y+1, bw, bh, colors.gray)
    box(x, y, bw, bh, colors.blue)
    writeAt(x+1, y, " Run: ", colors.blue, colors.yellow)
    writeAt(x+1, y+1, " > "..state.runQuery.."_", colors.blue, colors.white)
    writeAt(x+1, y+2, " Enter=run  Esc=cancel ", colors.blue, colors.lightGray)
end

local function drawMenu()
    if not state.menuOpen then return end
    local items = {}
    local menuX = 1
    if state.menuOpen == "archos" then
        menuX = 2
        items = {
            {"Run... (F1)", function()
                state.runDialogOpen = true
                state.runQuery = ""
            end},
            {"Logout", function()
                state.running = false
            end},
            {"Reboot", function() os.reboot() end},
            {"Power Off", function() os.shutdown() end},
        }
    elseif state.menuOpen == "apps" then
        menuX = 9
        for _, app in ipairs(state.apps) do
            table.insert(items, {app.name, function()
                local offset = #state.windows * 2
                local win = Window.new(app, 5 + offset, 4 + offset)
                win:start()
                table.insert(state.windows, win)
                state.activeWindow = win
            end})
        end
    elseif state.menuOpen == "system" then
        menuX = 14
        items = {
            {"Settings", function()
                local win = Window.new({name="Settings", path="/usr/bin/settings.lua", icon="S", color=colors.lightGray})
                win:start(); table.insert(state.windows, win); state.activeWindow = win
            end},
            {"System Monitor", function()
                local win = Window.new({name="Monitor", path="/usr/bin/system-monitor.lua", icon="M", color=colors.red})
                win:start(); table.insert(state.windows, win); state.activeWindow = win
            end},
            {"Task Manager", function()
                local win = Window.new({name="Tasks", path="/usr/bin/taskmgr.lua", icon="K", color=colors.cyan})
                win:start(); table.insert(state.windows, win); state.activeWindow = win
            end},
            {"Print File", function()
                local win = Window.new({name="Print", path="/usr/bin/print.lua", icon="PR", color=colors.red})
                win:start(); table.insert(state.windows, win); state.activeWindow = win
            end},
            {"Update", function()
                local win = Window.new({name="Update", path="/bin/update.lua", icon="U", color=colors.green})
                win:start(); table.insert(state.windows, win); state.activeWindow = win
            end},
            {"Cleanup", function()
                local win = Window.new({name="Cleanup", path="/bin/cleanup.lua", icon="C", color=colors.yellow})
                win:start(); table.insert(state.windows, win); state.activeWindow = win
            end},
        }
    end
    local mw = 25
    local mh = #items + 2
    box(menuX, 2, mw, mh, colors.lightGray)
    writeAt(menuX+1, 2, " "..state.menuOpen.." ", colors.lightGray, colors.black)
    for i, item in ipairs(items) do
        local label = item[1]
        if #label > mw-3 then label = label:sub(1, mw-3) end
        writeAt(menuX+1, 2+i, " "..label..string.rep(" ", mw-#label-3), colors.lightGray, colors.black)
    end
    reset()
    state.menuItems = items
    state.menuX = menuX
    state.menuW = mw
end

local function render()
    local w, h = term.getSize()
    box(1, 1, w, h, colors.black)
    if not loginState.loggedIn then
        drawLoginScreen()
        return
    end
    drawMenuBar()
    drawDesktopIcons()
    drawWindows()
    drawTaskbar()
    if state.menuOpen then drawMenu() end
    if state.runDialogOpen then drawRunDialog() end
end

-- ============================================================
--  Main loop
-- ============================================================

local function main()
    state.apps = loadApps()
    state.clock = os.date("%H:%M")
    local clockTimer = os.startTimer(30)
    local tickTimer = os.startTimer(0.1)

    while state.running do
        local ok, err = pcall(function()
            render()
            local event = {os.pullEvent()}

            -- NOT LOGGED IN: handle login events
            if not loginState.loggedIn then
                handleLoginEvent(event)
                return
            end

            -- Timer: tick all alive windows
            if event[1] == "timer" and event[2] == tickTimer then
                for _, win in ipairs(state.windows) do
                    if win.alive and not win.minimized then
                        win:_resume(event)
                    end
                end
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

            -- Run dialog
            if state.runDialogOpen then
                if event[1] == "char" then
                    state.runQuery = state.runQuery .. event[2]
                elseif event[1] == "key" then
                    if event[2] == keys.enter then
                        local q = state.runQuery
                        state.runDialogOpen = false
                        state.runQuery = ""
                        for _, app in ipairs(state.apps) do
                            if app.name:lower():find(q:lower()) then
                                local offset = #state.windows * 2
                                local win = Window.new(app, 5+offset, 4+offset)
                                win:start()
                                table.insert(state.windows, win)
                                state.activeWindow = win
                                return
                            end
                        end
                        local path = q
                        if not path:match("^/") then
                            for _, d in ipairs({"/bin","/usr/bin"}) do
                                local p = d.."/"..q
                                if not p:match("%.lua$") then p = p..".lua" end
                                if fs.exists(p) then path = p; break end
                            end
                        end
                        if fs.exists(path) then
                            local win = Window.new({name=q, path=path, icon="?", color=colors.lightGray})
                            win:start()
                            table.insert(state.windows, win)
                            state.activeWindow = win
                        end
                    elseif event[2] == keys.backspace then
                        state.runQuery = state.runQuery:sub(1,-2)
                    elseif event[2] == keys.escape then
                        state.runDialogOpen = false
                        state.runQuery = ""
                    end
                end
                return
            end

            -- Key events → deliver to active window
            if event[1] == "key" then
                if event[2] == keys.f1 then
                    state.runDialogOpen = not state.runDialogOpen
                    state.runQuery = ""
                    state.menuOpen = nil
                elseif event[2] == keys.escape then
                    state.menuOpen = nil
                elseif state.activeWindow and state.activeWindow.alive then
                    -- DELIVER KEY EVENT TO ACTIVE WINDOW
                    state.activeWindow:resumeKey(event[1], event[2])
                end
                return
            end

            -- Char events → deliver to active window
            if event[1] == "char" then
                if state.activeWindow and state.activeWindow.alive then
                    state.activeWindow:resumeKey(event[1], event[2])
                end
                return
            end

            -- Paste events → active window
            if event[1] == "paste" then
                if state.activeWindow and state.activeWindow.alive then
                    state.activeWindow:resumeKey(event[1], event[2])
                end
                return
            end

            -- Mouse events
            if event[1] == "mouse_click" then
                local btn, x, y = event[2], event[3], event[4]
                local w, h = term.getSize()

                -- Menu bar
                if y == 1 then
                    if x >= 2 and x <= 7 then
                        state.menuOpen = state.menuOpen == "archos" and nil or "archos"
                    elseif x >= 9 and x <= 12 then
                        state.menuOpen = state.menuOpen == "apps" and nil or "apps"
                    elseif x >= 14 and x <= 20 then
                        state.menuOpen = state.menuOpen == "system" and nil or "system"
                    else
                        state.menuOpen = nil
                    end
                    return
                end

                -- Menu item click
                if state.menuOpen and state.menuItems then
                    if x >= state.menuX and x < state.menuX + state.menuW
                       and y > 2 and y <= 2 + #state.menuItems then
                        local item = state.menuItems[y - 2]
                        if item then
                            state.menuOpen = nil
                            state.menuItems = nil
                            item[2]()
                        end
                    else
                        state.menuOpen = nil
                        state.menuItems = nil
                    end
                    return
                end

                -- Taskbar
                if y == h then
                    local tbX = 2
                    for _, win in ipairs(state.windows) do
                        if win.minimized then
                            local label = win.title:sub(1,12)
                            local bw = #label + 4
                            if x >= tbX and x < tbX + bw then
                                win:restore()
                                state.activeWindow = win
                                return
                            end
                            tbX = tbX + bw
                        end
                    end
                    return
                end

                -- Check windows (front to back)
                for i = #state.windows, 1, -1 do
                    local win = state.windows[i]
                    if not win.minimized and win:contains(x, y) then
                        -- Bring to front
                        table.remove(state.windows, i)
                        table.insert(state.windows, win)
                        state.activeWindow = win

                        if win:onCloseButton(x, y) then
                            win:close()
                        elseif win:onMinButton(x, y) then
                            win:minimize()
                            state.activeWindow = nil
                        elseif win:onMaxButton(x, y) then
                            win:toggleMaximize()
                        elseif win:onTitleBar(x, y) then
                            state.dragging = {window=win, offsetX=x-win.x, offsetY=y-win.y, type="move"}
                        elseif win:onResizeHandle(x, y) then
                            state.dragging = {window=win, type="resize"}
                        elseif win:inContent(x, y) then
                            -- Deliver mouse click to window
                            win:resumeMouse("mouse_click", btn, x, y)
                        end
                        return
                    end
                end

                -- Desktop icon click
                for i, app in ipairs(state.apps) do
                    local ix = 2
                    local iy = 3 + (i-1)*4
                    if x >= ix and x <= ix+3 and y >= iy and y <= iy+2 then
                        local offset = #state.windows * 2
                        local win = Window.new(app, 5+offset, 4+offset)
                        win:start()
                        table.insert(state.windows, win)
                        state.activeWindow = win
                        return
                    end
                end
            end

            -- Mouse drag
            if event[1] == "mouse_drag" and state.dragging then
                local drag = state.dragging
                if drag.type == "move" then
                    drag.window:move(event[3] - drag.offsetX, event[4] - drag.offsetY)
                elseif drag.type == "resize" then
                    drag.window:resize(event[3] - drag.window.x + 1, event[4] - drag.window.y + 1)
                end
                return
            end

            -- Mouse up → deliver to active window if in content, or stop dragging
            if event[1] == "mouse_up" then
                if state.dragging then
                    state.dragging = nil
                elseif state.activeWindow and state.activeWindow.alive then
                    local _, _, x, y = unpack(event)
                    if state.activeWindow:inContent(x, y) then
                        state.activeWindow:resumeMouse("mouse_up", event[2], x, y)
                    end
                end
                return
            end

            -- Mouse scroll → active window
            if event[1] == "mouse_scroll" then
                if state.activeWindow and state.activeWindow.alive then
                    local _, _, _, x, y = unpack(event)
                    if state.activeWindow:inContent(x, y) then
                        state.activeWindow:resumeMouse("mouse_scroll", event[2], event[3], event[4])
                    end
                end
                return
            end
        end)

        if not ok then
            setColor(colors.red)
            term.setCursorPos(1, select(2, term.getSize()))
            term.write("[gui err] " .. tostring(err):sub(1, 40))
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
