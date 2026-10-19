--[[
    de/gnome.lua  —  GNOME-like Desktop Environment (simpler GUI)
    ============================================================
    A clean, minimalist graphical desktop inspired by GNOME 3:
      * Top bar with system menu, clock, and status indicators
      * Application launcher (activities view) on Super key
      * Application windows that can be moved and closed
      * Right-click desktop context menu
      * Workspace overview

    Drawing uses term/paintutils primitives. No window manager effects.

    Layout:
      +--------------------------------------------------+
      |  Activities  ArchOS-CC   HH:MM   ●Battery  ▼Menu |  <- top bar (height 1)
      +--------------------------------------------------+
      |                                                  |
      |       Desktop icons (left-aligned, vertical)     |
      |                                                  |
      |       Floating application windows              |
      |                                                  |
      +--------------------------------------------------+

    Hotkeys:
      Super / Tab  : open Activities overview
      Right-click  : desktop context menu
      Click top bar : system menu
--]]

local GNOME = {}

-- State
local state = {
    windows = {},        -- list of window objects
    nextWindowID = 1,
    activitiesOpen = false,
    systemMenuOpen = false,
    contextMenu = nil,   -- {x, y, items}
    clock = "00:00",
    background = colors.black,
    topBarColor = colors.black,
    topBarFgColor = colors.white,
    accentColor = colors.lightBlue,
    desktopIcons = {},
    running = false,
}

-- Desktop icon definitions
local function loadDesktopIcons()
    state.desktopIcons = {
        { name = "Files",     icon = "F", color = colors.yellow, action = "/usr/bin/browser.lua" },
        { name = "Terminal",  icon = "T", color = colors.green, action = "/bin/sh.lua" },
        { name = "Editor",    icon = "E", color = colors.cyan, action = "/usr/bin/editor.lua" },
        { name = "Settings",  icon = "S", color = colors.lightGray, action = "/usr/bin/settings.lua" },
        { name = "Notes",     icon = "N", color = colors.orange, action = "/usr/bin/notes.lua" },
        { name = "Paint",     icon = "P", color = colors.magenta, action = "/usr/bin/paint.lua" },
        { name = "Calc",      icon = "C", color = colors.lime, action = "/usr/bin/calculator.lua" },
        { name = "Player",    icon = "M", color = colors.purple, action = "/usr/bin/player.lua" },
    }
end

-- Helper: clear the screen with background color
local function clearScreen()
    term.setBackgroundColor(state.background)
    term.clear()
end

-- Helper: draw a horizontal line of color
local function fillRow(y, color)
    local w = term.getSize()
    term.setBackgroundColor(color)
    term.setCursorPos(1, y)
    term.write(string.rep(" ", w))
end

-- Helper: draw a filled box (text-mode approximation)
local function drawBox(x, y, w, h, bg, fg)
    term.setBackgroundColor(bg)
    if fg then term.setTextColor(fg) end
    for row = y, y + h - 1 do
        term.setCursorPos(x, row)
        term.write(string.rep(" ", w))
    end
end

-- Helper: write text at position with colors
local function writeAt(x, y, text, bg, fg)
    if bg then term.setBackgroundColor(bg) end
    if fg then term.setTextColor(fg) end
    term.setCursorPos(x, y)
    term.write(text)
end

-- Draw top bar
local function drawTopBar()
    local w, h = term.getSize()
    fillRow(1, state.topBarColor)

    -- Left: Activities button
    writeAt(2, 1, "Activities", state.topBarColor, state.accentColor)

    -- Center: OS name
    writeAt(math.floor(w / 2) - 5, 1, "ArchOS-CC", state.topBarColor, state.topBarFgColor)

    -- Right: clock + menu
    writeAt(w - #state.clock - 1, 1, state.clock, state.topBarColor, state.topBarFgColor)
    writeAt(w, 1, "v", state.topBarColor, state.accentColor)
end

-- Draw desktop icons
local function drawDesktopIcons()
    local startX = 2
    local startY = 3
    local iconSize = 3
    for i, icon in ipairs(state.desktopIcons) do
        local x = startX
        local y = startY + (i - 1) * (iconSize + 1)

        -- Icon background
        drawBox(x, y, 3, 3, icon.color)
        -- Letter in icon
        writeAt(x + 1, y + 1, icon.icon, icon.color, colors.black)
        -- Label below
        if y + 3 <= select(2, term.getSize()) then
            writeAt(x - 1, y + 3, " " .. icon.name .. " ", state.background, colors.white)
        end
    end
end

-- Draw a window (decorated box)
local function drawWindow(win)
    -- Window has: x, y, width, height, title, content (string)
    drawBox(win.x, win.y, win.width, win.height, colors.black)
    -- Title bar
    drawBox(win.x, win.y, win.width, 1, state.accentColor)
    writeAt(win.x + 1, win.y, win.title, state.accentColor, colors.white)
    -- Close button
    writeAt(win.x + win.width - 1, win.y, "X", state.accentColor, colors.white)
    -- Content
    if win.content then
        local lineY = win.y + 2
        for line in win.content:gmatch("[^\n]*") do
            if lineY >= win.y + win.height then break end
            writeAt(win.x + 1, lineY, line, colors.black, colors.white)
            lineY = lineY + 1
        end
    end
end

-- Draw activities overview (full-screen launcher)
local function drawActivities()
    local w, h = term.getSize()
    -- Dim background
    drawBox(1, 1, w, h, colors.gray)
    -- Title
    writeAt(math.floor(w / 2) - 5, 2, "Applications", colors.gray, colors.white)

    -- Grid of apps
    local apps = {
        { name = "Terminal", icon = "T", action = "/bin/sh.lua" },
        { name = "Files",    icon = "F", action = "/usr/bin/browser.lua" },
        { name = "Editor",   icon = "E", action = "/usr/bin/editor.lua" },
        { name = "Settings", icon = "S", action = "/usr/bin/settings.lua" },
        { name = "Notes",    icon = "N", action = "/usr/bin/notes.lua" },
        { name = "Paint",    icon = "P", action = "/usr/bin/paint.lua" },
        { name = "Calc",     icon = "C", action = "/usr/bin/calculator.lua" },
        { name = "Music",    icon = "M", action = "/usr/bin/player.lua" },
        { name = "Top",      icon = "T", action = "/usr/bin/top.lua" },
        { name = "Neofetch", icon = "N", action = "/usr/bin/neofetch.lua" },
        { name = "Lua REPL", icon = "L", action = "/usr/bin/lua-repl.lua" },
        { name = "TaskMgr",  icon = "K", action = "/usr/bin/taskmgr.lua" },
        { name = "SysMgr",   icon = "S", action = "/usr/bin/sysmgr.lua" },
        { name = "Redstone", icon = "R", action = "/usr/bin/redstone-panel.lua" },
        { name = "Monitor",  icon = "M", action = "/usr/bin/monitor-app.lua" },
        { name = "Browser",  icon = "B", action = "/usr/bin/gbrowse.lua" },
    }

    local cols = 4
    local cellW = math.floor(w / cols)
    local cellH = 4
    local startY = 4
    for i, app in ipairs(apps) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = 1 + col * cellW + math.floor(cellW / 2) - 2
        local y = startY + row * (cellH + 1)
        if y + cellH < h then
            -- Icon box
            drawBox(x, y, 4, 3, colors.lightGray)
            writeAt(x + 1, y + 1, app.icon, colors.lightGray, colors.black)
            -- Label
            writeAt(x, y + 3, app.name:sub(1, cellW), colors.gray, colors.white)
        end
    end

    -- Hint
    writeAt(1, h, "Click an app to launch  |  Press ESC to close", colors.gray, colors.yellow)
end

-- Draw system menu (top-right dropdown)
local function drawSystemMenu()
    local w, h = term.getSize()
    local menuW = 20
    local menuH = 6
    local x = w - menuW
    local y = 2

    drawBox(x, y, menuW, menuH, colors.lightGray)
    writeAt(x + 1, y + 0, " System Menu    ", colors.lightGray, colors.black)
    writeAt(x + 1, y + 1, " Settings       ", colors.lightGray, colors.black)
    writeAt(x + 1, y + 2, " Lock           ", colors.lightGray, colors.black)
    writeAt(x + 1, y + 3, " Reboot         ", colors.lightGray, colors.red)
    writeAt(x + 1, y + 4, " Power Off      ", colors.lightGray, colors.red)
    writeAt(x + 1, y + 5, " Logout         ", colors.lightGray, colors.black)
end

-- Draw context menu
local function drawContextMenu()
    if not state.contextMenu then return end
    local cm = state.contextMenu
    local x, y = cm.x, cm.y
    local menuW = 16
    local menuH = #cm.items
    drawBox(x, y, menuW, menuH, colors.lightGray)
    for i, item in ipairs(cm.items) do
        writeAt(x + 1, y + i - 1, item.label:sub(1, menuW - 2), colors.lightGray, colors.black)
    end
end

-- Full render
local function render()
    clearScreen()
    drawTopBar()
    drawDesktopIcons()

    for _, win in ipairs(state.windows) do
        drawWindow(win)
    end

    if state.activitiesOpen then drawActivities() end
    if state.systemMenuOpen then drawSystemMenu() end
    drawContextMenu()
end

-- Update clock
local function updateClock()
    state.clock = os.date("%H:%M")
end

-- Launch an application by path
local function launchApp(path)
    local Kernel = _G.Kernel
    if not Kernel then
        -- Fallback: just dofile in same process (loses window context)
        if fs.exists(path) then
            local oldTerm = term.redirect
            -- Save current screen state, then exec
            local ok, err = pcall(dofile, path)
            if not ok then
                print("[gnome] app crashed: " .. err)
                os.sleep(2)
            end
        end
        return
    end

    -- Spawn the app as a child process
    -- For simplicity, we don't yet give it a sub-window; it takes over the screen
    -- and returns to GNOME when done.
    render()  -- clear ourselves first
    local pid = Kernel.exec(path, {})
    if pid then
        Kernel.wait(pid)
    end
end

-- Main event loop
local function mainLoop()
    state.running = true
    local clockTimer = os.startTimer(30)  -- update clock every 30s

    while state.running do
        render()
        local event = { os.pullEvent() }

        if event[1] == "timer" and event[2] == clockTimer then
            updateClock()
            clockTimer = os.startTimer(30)
        elseif event[1] == "key" then
            if event[2] == keys.leftCtrl or event[2] == keys.rightCtrl then
                -- Ignore; wait for next key
            elseif event[2] == keys.leftAlt or event[2] == keys.rightAlt then
                state.activitiesOpen = not state.activitiesOpen
            elseif event[2] == keys.escape then
                state.activitiesOpen = false
                state.systemMenuOpen = false
                state.contextMenu = nil
            elseif event[2] == keys.q then
                state.running = false
            end
        elseif event[1] == "char" then
            -- Could add shortcuts here
        elseif event[1] == "mouse_click" then
            local button, x, y = event[2], event[3], event[4]
            if button == 1 then
                -- Left click
                if state.activitiesOpen then
                    -- Click on app grid
                    local w, h = term.getSize()
                    local apps = {
                        { name = "Terminal", action = "/bin/sh.lua" },
                        { name = "Files",    action = "/usr/bin/browser.lua" },
                        { name = "Editor",   action = "/usr/bin/editor.lua" },
                        { name = "Settings", action = "/usr/bin/settings.lua" },
                        { name = "Notes",    action = "/usr/bin/notes.lua" },
                        { name = "Paint",    action = "/usr/bin/paint.lua" },
                        { name = "Calc",     action = "/usr/bin/calculator.lua" },
                        { name = "Music",    action = "/usr/bin/player.lua" },
                        { name = "Top",      action = "/usr/bin/top.lua" },
                        { name = "Neofetch", action = "/usr/bin/neofetch.lua" },
                        { name = "Lua REPL", action = "/usr/bin/lua-repl.lua" },
                        { name = "TaskMgr",  action = "/usr/bin/taskmgr.lua" },
                        { name = "SysMgr",   action = "/usr/bin/sysmgr.lua" },
                        { name = "Redstone", action = "/usr/bin/redstone-panel.lua" },
                        { name = "Monitor",  action = "/usr/bin/monitor-app.lua" },
                        { name = "Browser",  action = "/usr/bin/gbrowse.lua" },
                    }
                    local cols = 4
                    local cellW = math.floor(w / cols)
                    local cellH = 4
                    local startY = 4
                    for i, app in ipairs(apps) do
                        local col = (i - 1) % cols
                        local row = math.floor((i - 1) / cols)
                        local cellX = 1 + col * cellW
                        local cellY = startY + row * (cellH + 1)
                        if x >= cellX and x < cellX + cellW and y >= cellY and y < cellY + cellH then
                            state.activitiesOpen = false
                            launchApp(app.action)
                            break
                        end
                    end
                elseif state.systemMenuOpen then
                    -- Handle menu click
                    local w = term.getSize()
                    local menuW = 20
                    local menuX = w - menuW
                    if x >= menuX then
                        if y == 3 then launchApp("/usr/bin/settings.lua"); state.systemMenuOpen = false
                        elseif y == 5 then os.reboot()
                        elseif y == 6 then os.shutdown()
                        elseif y == 7 then state.running = false
                        else state.systemMenuOpen = false end
                    else
                        state.systemMenuOpen = false
                    end
                elseif state.contextMenu then
                    -- Handle context menu click
                    local cm = state.contextMenu
                    if x >= cm.x and x < cm.x + 16 then
                        local idx = y - cm.y + 1
                        if cm.items[idx] then
                            cm.items[idx].action()
                        end
                    end
                    state.contextMenu = nil
                elseif y == 1 then
                    -- Top bar click
                    local w = term.getSize()
                    if x <= 11 then
                        state.activitiesOpen = not state.activitiesOpen
                    elseif x >= w - 1 then
                        state.systemMenuOpen = not state.systemMenuOpen
                    end
                else
                    -- Click on desktop - check if on an icon
                    local found = false
                    for i, icon in ipairs(state.desktopIcons) do
                        local iconY = 3 + (i - 1) * 4
                        if x >= 2 and x <= 4 and y >= iconY and y <= iconY + 2 then
                            launchApp(icon.action)
                            found = true
                            break
                        end
                    end
                    if not found then
                        -- Click on empty desktop - check windows for close button
                        for _, win in ipairs(state.windows) do
                            if x == win.x + win.width - 1 and y == win.y then
                                -- Close button
                                win.closed = true
                            end
                        end
                        -- Remove closed windows
                        local newWins = {}
                        for _, win in ipairs(state.windows) do
                            if not win.closed then table.insert(newWins, win) end
                        end
                        state.windows = newWins
                    end
                end
            elseif button == 2 then
                -- Right click - show context menu
                state.contextMenu = {
                    x = x, y = y,
                    items = {
                        { label = "Open Terminal", action = function() launchApp("/bin/sh.lua") end },
                        { label = "Open Files",    action = function() launchApp("/usr/bin/browser.lua") end },
                        { label = "Activities",    action = function() state.activitiesOpen = true end },
                        { label = "Settings",      action = function() launchApp("/usr/bin/settings.lua") end },
                        { label = "Logout",       action = function() state.running = false end },
                    }
                }
            end
        end
    end
end

local function main()
    -- Run login first to authenticate user
    -- If no root password, skip; otherwise prompt
    if fs.exists("/bin/login.lua") and _G.Kernel then
        local pid = _G.Kernel.exec("/bin/login.lua", {})
        if pid then _G.Kernel.wait(pid) end
    end

    loadDesktopIcons()
    updateClock()
    mainLoop()

    -- Clean up
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    return 0
end

return main()
