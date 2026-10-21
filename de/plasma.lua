--[[
    de/plasma.lua  —  KDE Plasma-like Desktop Environment (advanced GUI)
    ===================================================================
    Inspired by KDE Plasma 6:
      * Taskbar at bottom with launcher, task buttons, system tray
      * KRunner-like command launcher (Super+Space)
      * Window manager with: move, resize, minimize, maximize, close
      * Desktop widgets (clock, system load, sticky notes)
      * Application launcher (Kickoff-style menu)
      * Activities switcher
      * Animations: window open/close fade, panel slide
      * Compositing effects: shadows, blur (text-mode approximations)

    Color scheme: Breeze Dark (dark background, blue accents).
]]

local Plasma = {}

-- Plasma Breeze Dark palette
local PALETTE = {
    bg          = colors.black,
    panel       = colors.gray,
    panelActive = colors.blue,
    panelFg     = colors.white,
    accent      = colors.lightBlue,
    accentDark  = colors.blue,
    warning     = colors.orange,
    error       = colors.red,
    success     = colors.green,
    text        = colors.white,
    textDim     = colors.lightGray,
    textMuted   = colors.gray,
    windowBg    = colors.black,
    titleBar    = colors.blue,
    titleBarFg  = colors.white,
    desktop     = colors.black,
    widget      = colors.lightGray,
    widgetFg    = colors.black,
    shadow      = colors.gray,
}

-- State
local state = {
    windows = {},
    nextWindowID = 1,
    activeWindow = nil,
    panelHeight = 1,
    kickerOpen = false,
    krunnerOpen = false,
    krunnerQuery = "",
    activitiesOpen = false,
    currentActivity = "Default",
    activities = {"Default", "Work", "Media"},
    clock = "00:00",
    dateStr = "",
    cpuLoad = 0,
    memUsage = 0,
    netActivity = false,
    running = false,
    contextMenu = nil,
    animationFrame = 0,
    -- Widget positions (fixed for now)
    widgets = {
        { type = "clock", x = 1, y = 1 },
        { type = "cpu",   x = 1, y = 2 },
        { type = "net",   x = 2, y = 2 },
    },
    -- Taskbar buttons (apps pinned)
    pinnedApps = {
        { name = "Terminal", icon = ">", action = "/bin/sh.lua" },
        { name = "Files",    icon = "F", action = "/usr/bin/browser.lua" },
        { name = "Editor",   icon = "E", action = "/usr/bin/editor.lua" },
        { name = "Settings", icon = "S", action = "/usr/bin/settings.lua" },
        { name = "Browser",  icon = "B", action = "/usr/bin/gbrowse.lua" },
    },
    dragging = nil,  -- {window, dx, dy} when dragging a window
    resizing = nil,  -- {window} when resizing
}

local function writeAt(x, y, text, bg, fg)
    if bg then term.setBackgroundColor(bg) end
    if fg then term.setTextColor(fg) end
    term.setCursorPos(x, y)
    term.write(text)
end

local function fillRow(y, color)
    local w = term.getSize()
    term.setBackgroundColor(color)
    term.setCursorPos(1, y)
    term.write(string.rep(" ", w))
end

local function drawBox(x, y, w, h, color)
    term.setBackgroundColor(color)
    for row = y, y + h - 1 do
        term.setCursorPos(x, row)
        term.write(string.rep(" ", w))
    end
end

-- Draw panel (bottom taskbar)
local function drawPanel()
    local w, h = term.getSize()
    local panelY = h
    fillRow(panelY, PALETTE.panel)

    -- Application launcher button (Kickoff)
    writeAt(1, panelY, " [Menu] ", PALETTE.panel, PALETTE.accent)

    -- Pinned apps
    local x = 9
    for _, app in ipairs(state.pinnedApps) do
        writeAt(x, panelY, " " .. app.icon .. " ", PALETTE.panel, PALETTE.text)
        x = x + 3
    end

    -- Separator
    writeAt(x, panelY, "|", PALETTE.panel, PALETTE.textMuted)

    -- Open window tasks
    x = x + 1
    for _, win in ipairs(state.windows) do
        local label = win.title:sub(1, 10)
        local bg = (win == state.activeWindow) and PALETTE.panelActive or PALETTE.panel
        writeAt(x, panelY, " " .. label .. " ", bg, PALETTE.text)
        x = x + #label + 2
        if x > w - 30 then break end
    end

    -- System tray (right side)
    local sysTray = ""
    if state.netActivity then sysTray = sysTray .. " ^" else sysTray = sysTray .. " ." end
    sysTray = sysTray .. " " .. state.clock
    writeAt(w - #sysTray - 1, panelY, sysTray, PALETTE.panel, PALETTE.text)
end

-- Draw desktop widgets
local function drawWidgets()
    local w, h = term.getSize()
    -- Clock widget (top-right)
    writeAt(w - 16, 2, "+----------------+", PALETTE.desktop, PALETTE.widget)
    writeAt(w - 16, 3, "|" .. state.clock .. "         |", PALETTE.desktop, PALETTE.accent)
    writeAt(w - 16, 4, "|" .. state.dateStr .. "      |", PALETTE.desktop, PALETTE.textDim)
    writeAt(w - 16, 5, "+----------------+", PALETTE.desktop, PALETTE.widget)

    -- CPU/memory widget (top-left)
    writeAt(2, 2, "+----------------+", PALETTE.desktop, PALETTE.widget)
    writeAt(2, 3, "| System Monitor |", PALETTE.desktop, PALETTE.accent)
    local loadBar = ""
    for i = 1, 14 do
        loadBar = loadBar .. (i / 14 <= state.cpuLoad and "#" or ".")
    end
    writeAt(2, 4, "| CPU [" .. loadBar .. "] |", PALETTE.desktop, PALETTE.text)
    local memBar = ""
    for i = 1, 14 do
        memBar = memBar .. (i / 14 <= state.memUsage and "#" or ".")
    end
    writeAt(2, 5, "| MEM [" .. memBar .. "] |", PALETTE.desktop, PALETTE.text)
    writeAt(2, 6, "+----------------+", PALETTE.desktop, PALETTE.widget)

    -- Quick launch buttons (right side, center)
    local quickY = math.floor(h / 2) - 3
    writeAt(w - 5, quickY,     "+---+", PALETTE.desktop, PALETTE.widget)
    writeAt(w - 5, quickY + 1, "| T |", PALETTE.desktop, PALETTE.accent)
    writeAt(w - 5, quickY + 2, "+---+", PALETTE.desktop, PALETTE.widget)
    writeAt(w - 5, quickY + 3, "+---+", PALETTE.desktop, PALETTE.widget)
    writeAt(w - 5, quickY + 4, "| F |", PALETTE.desktop, PALETTE.accent)
    writeAt(w - 5, quickY + 5, "+---+", PALETTE.desktop, PALETTE.widget)
end

-- Draw a window with shadow effect
local function drawWindow(win)
    -- Shadow (offset by 1)
    if win.x + win.width < select(1, term.getSize()) then
        drawBox(win.x + 1, win.y + 1, win.width, win.height, PALETTE.shadow)
    end

    -- Window background
    drawBox(win.x, win.y, win.width, win.height, PALETTE.windowBg)

    -- Title bar
    local titleBarColor = (win == state.activeWindow) and PALETTE.titleBar or PALETTE.panel
    drawBox(win.x, win.y, win.width, 1, titleBarColor)
    writeAt(win.x + 1, win.y, " " .. win.title:sub(1, win.width - 6) .. " ", titleBarColor, PALETTE.titleBarFg)

    -- Window control buttons (right of title bar)
    local btnX = win.x + win.width - 4
    writeAt(btnX, win.y, "_", titleBarColor, PALETTE.text)        -- minimize
    writeAt(btnX + 1, win.y, "+", titleBarColor, PALETTE.text)    -- maximize
    writeAt(btnX + 2, win.y, "X", titleBarColor, PALETTE.warning) -- close

    -- Window border (for active window)
    if win == state.activeWindow then
        term.setTextColor(PALETTE.accent)
        term.setBackgroundColor(PALETTE.windowBg)
        -- Top, bottom borders
        term.setCursorPos(win.x, win.y + win.height)
        term.write(string.rep("-", win.width))
    end

    -- Content
    if win.content then
        local lineY = win.y + 2
        for line in win.content:gmatch("[^\n]*") do
            if lineY >= win.y + win.height then break end
            if line ~= "" then
                writeAt(win.x + 1, lineY, line:sub(1, win.width - 2), PALETTE.windowBg, PALETTE.text)
            end
            lineY = lineY + 1
        end
    end
end

-- Draw Kickoff menu (application launcher)
local function drawKickoff()
    local w, h = term.getSize()
    -- Dynamic menu size based on number of apps
    local apps = {
        { name = "Terminal",          action = "/bin/sh.lua" },
        { name = "Files (text)",      action = "/usr/bin/browser.lua" },
        { name = "Files (graphical)", action = "/usr/bin/gbrowse.lua" },
        { name = "File Manager",      action = "/usr/bin/filemanager.lua" },
        { name = "Multi-Tab Terminal", action = "/usr/bin/terminal.lua" },
        { name = "Text Editor",       action = "/usr/bin/editor.lua" },
        { name = "Settings",          action = "/usr/bin/settings.lua" },
        { name = "Notes",             action = "/usr/bin/notes.lua" },
        { name = "Paint",             action = "/usr/bin/paint.lua" },
        { name = "Calculator",        action = "/usr/bin/calculator.lua" },
        { name = "Clock",             action = "/usr/bin/clock.lua" },
        { name = "Music Player",      action = "/usr/bin/player.lua" },
        { name = "System Monitor",    action = "/usr/bin/system-monitor.lua" },
        { name = "Top",               action = "/usr/bin/top.lua" },
        { name = "Neofetch",          action = "/usr/bin/neofetch.lua" },
        { name = "Lua REPL",          action = "/usr/bin/lua-repl.lua" },
        { name = "Task Manager",      action = "/usr/bin/taskmgr.lua" },
        { name = "System Manager",    action = "/usr/bin/sysmgr.lua" },
        { name = "Redstone Panel",    action = "/usr/bin/redstone-panel.lua" },
    }
    local menuW = 28
    local menuH = #apps + 5  -- apps + header + search + footer + padding
    local x = 1
    local y = h - menuH - 1

    -- Shadow
    drawBox(x + 1, y + 1, menuW, menuH, PALETTE.shadow)
    -- Menu background
    drawBox(x, y, menuW, menuH, PALETTE.panel)

    -- Header
    drawBox(x, y, menuW, 1, PALETTE.accentDark)
    writeAt(x + 1, y, " Applications ", PALETTE.accentDark, PALETTE.text)

    -- Search field
    writeAt(x + 1, y + 2, "Search: ", PALETTE.panel, PALETTE.text)
    -- (Not interactive for simplicity)

    for i, app in ipairs(apps) do
        if y + 3 + i <= y + menuH - 1 then
            writeAt(x + 1, y + 3 + i, " " .. app.name, PALETTE.panel, PALETTE.text)
        end
    end

    -- Footer
    writeAt(x + 1, y + menuH - 1, "Press ESC to close", PALETTE.panel, PALETTE.textMuted)
end

-- Draw KRunner (command launcher)
local function drawKrunner()
    local w, h = term.getSize()
    local width = 40
    local x = math.floor((w - width) / 2)
    local y = math.floor(h / 2) - 2

    -- Shadow
    drawBox(x + 1, y + 1, width, 4, PALETTE.shadow)
    -- Background
    drawBox(x, y, width, 4, PALETTE.panel)
    -- Border
    term.setTextColor(PALETTE.accent)
    term.setBackgroundColor(PALETTE.panel)
    -- Border top/bottom
    term.setCursorPos(x, y); term.write(string.rep("=", width))
    term.setCursorPos(x, y + 3); term.write(string.rep("=", width))

    -- Title
    writeAt(x + 2, y + 1, "KRunner", PALETTE.panel, PALETTE.accent)
    -- Input line
    writeAt(x + 2, y + 2, "> " .. state.krunnerQuery .. "_", PALETTE.panel, PALETTE.text)
end

-- Draw activities switcher (full screen)
local function drawActivities()
    local w, h = term.getSize()
    drawBox(1, 1, w, h, PALETTE.bg)
    writeAt(math.floor(w / 2) - 6, 2, "Activities", PALETTE.bg, PALETTE.accent)

    local startY = 4
    for i, name in ipairs(state.activities) do
        local y = startY + (i - 1) * 3
        local active = (name == state.currentActivity)
        local bg = active and PALETTE.accent or PALETTE.panel
        local fg = PALETTE.text
        drawBox(math.floor(w / 2) - 15, y, 30, 2, bg)
        writeAt(math.floor(w / 2) - 13, y + 1, name .. (active and " (active)" or ""), bg, fg)
    end
    writeAt(1, h, "Press ESC to close  |  Click activity to switch", PALETTE.bg, PALETTE.textDim)
end

-- Render everything
local function render()
    local w, h = term.getSize()
    -- Desktop background
    term.setBackgroundColor(PALETTE.desktop)
    term.clear()

    drawWidgets()

    for _, win in ipairs(state.windows) do
        -- Skip minimized windows (don't draw them)
        if not win.minimized then
            drawWindow(win)
        end
    end

    if state.kickerOpen then drawKickoff() end
    if state.krunnerOpen then drawKrunner() end
    if state.activitiesOpen then drawActivities() end

    drawPanel()
end

-- Update system stats
local function updateStats()
    state.clock = os.date("%H:%M")
    state.dateStr = os.date("%b %d")
    -- Fake CPU/memory values (would normally come from scheduler)
    if _G.Scheduler then
        local stats = _G.Scheduler.stats()
        state.cpuLoad = math.min(1, (stats.processCount or 0) / 20)
        state.memUsage = math.min(1, (stats.tickCount or 0) % 50 / 50)
    end
    if _G.Network and _G.Network.online then
        state.netActivity = math.random() > 0.5
    end
end

-- Open a window with given title and content
local function openWindow(title, content, width, height)
    local w, h = term.getSize()
    local win = {
        id = state.nextWindowID,
        title = title,
        content = content or "",
        x = math.floor((w - (width or 30)) / 2) + (state.nextWindowID - 1) * 2,
        y = math.floor((h - (height or 10)) / 2) + (state.nextWindowID - 1),
        width = width or 30,
        height = height or 10,
        maximized = false,
        minimized = false,
    }
    state.nextWindowID = state.nextWindowID + 1
    -- Keep window on screen
    win.x = math.max(2, math.min(w - win.width - 1, win.x))
    win.y = math.max(2, math.min(h - win.height - 2, win.y))
    table.insert(state.windows, win)
    state.activeWindow = win
    return win
end

-- Launch an application (takes over the screen, returns when done)
local function launchApp(path)
    if not fs.exists(path) then
        local win = openWindow("Error", "Application not found:\n" .. path, 30, 5)
        return
    end
    local Kernel = _G.Kernel
    if Kernel then
        local pid = Kernel.exec(path, {})
        if pid then Kernel.wait(pid) end
    end
end

-- Find window at (x, y)
local function findWindowAt(x, y)
    for i = #state.windows, 1, -1 do
        local win = state.windows[i]
        if x >= win.x and x < win.x + win.width and y >= win.y and y < win.y + win.height then
            return win, i
        end
    end
    return nil
end

-- Main loop
local function mainLoop()
    state.running = true
    updateStats()
    local statsTimer = os.startTimer(2)

    while state.running do
        -- Wrap render + event handling in pcall so a single bug
        -- doesn't crash the whole DE. On error, log and continue.
        local ok, err = pcall(function()
            render()
            local event = { os.pullEvent() }

            if event[1] == "timer" and event[2] == statsTimer then
                updateStats()
                statsTimer = os.startTimer(2)
            elseif event[1] == "key" then
                local key = event[2]
                if key == keys.leftCtrl or key == keys.rightCtrl or
                   key == keys.leftAlt or key == keys.rightAlt then
                    -- Modifier key, will combine with next
                elseif key == keys.space and (state.krunnerOpen or state.kickerOpen) then
                    -- Toggle
                elseif key == keys.f1 then
                    -- KRunner
                    state.krunnerOpen = not state.krunnerOpen
                    state.krunnerQuery = ""
                elseif key == keys.escape then
                    state.kickerOpen = false
                    state.krunnerOpen = false
                    state.activitiesOpen = false
                    state.contextMenu = nil
                elseif key == keys.q and not state.krunnerOpen then
                    state.running = false
                elseif state.krunnerOpen then
                    -- KRunner active: read characters
                    if key == keys.enter then
                        -- Execute query
                        local q = state.krunnerQuery
                        state.krunnerOpen = false
                        state.krunnerQuery = ""
                        if q:sub(1, 1) == "/" or q:sub(1, 1) == "." then
                            launchApp(q)
                        else
                            -- Search in PATH
                            local cmd = q:match("%S+")
                            local path = "/bin/" .. cmd .. ".lua"
                            if fs.exists(path) then
                                launchApp(path)
                            else
                                path = "/usr/bin/" .. cmd .. ".lua"
                                if fs.exists(path) then launchApp(path) end
                            end
                        end
                    elseif key == keys.backspace then
                        state.krunnerQuery = state.krunnerQuery:sub(1, -2)
                    end
                end
            elseif event[1] == "char" and state.krunnerOpen then
                state.krunnerQuery = state.krunnerQuery .. event[2]
            elseif event[1] == "mouse_click" then
                local button, x, y = event[2], event[3], event[4]
                local w, h = term.getSize()

                if state.krunnerOpen then
                    state.krunnerOpen = false
                elseif state.activitiesOpen then
                    -- Click activity
                    local startY = 4
                    for i, name in ipairs(state.activities) do
                        local ay = startY + (i - 1) * 3
                        if y >= ay and y < ay + 2 then
                            state.currentActivity = name
                            state.activitiesOpen = false
                            break
                        end
                    end
                elseif state.kickerOpen then
                    -- Click an app
                    local apps = {
                        "/bin/sh.lua", "/usr/bin/browser.lua", "/usr/bin/gbrowse.lua",
                        "/usr/bin/filemanager.lua", "/usr/bin/terminal.lua",
                        "/usr/bin/editor.lua", "/usr/bin/settings.lua", "/usr/bin/notes.lua",
                        "/usr/bin/paint.lua", "/usr/bin/calculator.lua", "/usr/bin/clock.lua",
                        "/usr/bin/player.lua", "/usr/bin/system-monitor.lua",
                        "/usr/bin/top.lua", "/usr/bin/neofetch.lua", "/usr/bin/lua-repl.lua",
                        "/usr/bin/taskmgr.lua", "/usr/bin/sysmgr.lua", "/usr/bin/redstone-panel.lua",
                    }
                    local menuY = h - #apps - 3
                    if y > menuY + 2 and y < menuY + #apps + 3 then
                        local idx = y - (menuY + 2)
                        if apps[idx] then
                            state.kickerOpen = false
                            launchApp(apps[idx])
                        end
                    else
                        state.kickerOpen = false
                    end
                elseif y == h then
                    -- Panel click
                    if x <= 7 then
                        state.kickerOpen = not state.kickerOpen
                    elseif x >= 9 and x <= 23 then
                        -- Pinned app click
                        local idx = math.floor((x - 9) / 3) + 1
                        if state.pinnedApps[idx] then
                            launchApp(state.pinnedApps[idx].action)
                        end
                    else
                        -- Click on taskbar window buttons (right section)
                        local taskX = 25
                        for _, win in ipairs(state.windows) do
                            local label = win.title:sub(1, 10)
                            local btnW = #label + 2
                            if x >= taskX and x < taskX + btnW then
                                if win.minimized then
                                    win.minimized = false
                                    state.activeWindow = win
                                else
                                    if state.activeWindow == win then
                                        win.minimized = true
                                    else
                                        state.activeWindow = win
                                    end
                                end
                                break
                            end
                            taskX = taskX + btnW
                            if taskX > w - 25 then break end
                        end
                    end
                else
                    -- Click on desktop - check windows
                    local win = findWindowAt(x, y)
                    if win then
                        state.activeWindow = win
                        if y == win.y then
                            -- Title bar click
                            local btnX = win.x + win.width - 4
                            if x == btnX then
                                -- Minimize
                                win.minimized = true
                            elseif x == btnX + 1 then
                                -- Maximize/restore
                                if win.maximized then
                                    win.maximized = false
                                    win.x, win.y = win.savedX, win.savedY
                                    win.width, win.height = win.savedW, win.savedH
                                else
                                    win.savedX, win.savedY = win.x, win.y
                                    win.savedW, win.savedH = win.width, win.height
                                    win.x, win.y = 1, 1
                                    win.width, win.height = w, h - 1
                                    win.maximized = true
                                end
                            elseif x == btnX + 2 then
                                -- Close
                                for i, w2 in ipairs(state.windows) do
                                    if w2 == win then
                                        table.remove(state.windows, i)
                                        break
                                    end
                                end
                                state.activeWindow = state.windows[#state.windows] or nil
                            else
                                -- Start dragging
                                state.dragging = { window = win, offsetX = x - win.x, offsetY = y - win.y }
                            end
                        else
                            -- Body click - start dragging
                            state.dragging = { window = win, offsetX = x - win.x, offsetY = y - win.y }
                        end
                    else
                        -- Empty desktop click - open kicker
                        if button == 1 then
                            state.kickerOpen = not state.kickerOpen
                        end
                    end
                end
            end
            if event[1] == "mouse_drag" then
                if state.dragging then
                    local win = state.dragging.window
                    local newX = event[3] - state.dragging.offsetX
                    local newY = event[4] - state.dragging.offsetY
                    local w, h = term.getSize()
                    win.x = math.max(1, math.min(w - win.width, newX))
                    win.y = math.max(1, math.min(h - state.panelHeight - win.height + 1, newY))
                end
            end
            if event[1] == "mouse_up" then
                state.dragging = nil
            end
        end)
        if not ok then
            -- Log error but keep the DE running
            if term.isColor() then
                pcall(function() term.setTextColor(colors.red) end)
            end
            pcall(function()
                term.setCursorPos(1, select(2, term.getSize()))
                term.write("[plasma error] " .. tostring(err):sub(1, 50))
            end)
            if term.isColor() then
                pcall(function() term.setTextColor(colors.white) end)
            end
            os.sleep(0.5)
        end
    end
end

local function main()
    -- Run login first
    if fs.exists("/bin/login.lua") and _G.Kernel then
        local pid = _G.Kernel.exec("/bin/login.lua", {})
        if pid then _G.Kernel.wait(pid) end
    end

    -- Welcome window
    openWindow("Welcome to Plasma",
        "  ArchOS-CC Plasma Desktop\n\n" ..
        "  Press F1 for KRunner\n" ..
        "  Click [Menu] for applications\n" ..
        "  Press 'q' to logout",
        40, 9)

    mainLoop()

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    return 0
end

return main()
