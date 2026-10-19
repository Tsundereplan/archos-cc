--[[
    de/xfce.lua  —  XFCE-like Desktop Environment (lightweight GUI)
    ===============================================================
    Inspired by XFCE 4:
      * Single top panel with menu, task list, system tray, clock
      * Minimal desktop icons
      * Application windows with simple decoration (no shadows)
      * Right-click desktop for context menu
      * Lightweight - no animations, no compositing

    Color scheme: Adwaita-style light gray.
]]

local XFCE = {}

local PALETTE = {
    bg          = colors.white,
    panel       = colors.lightGray,
    panelFg     = colors.black,
    accent      = colors.blue,
    accentFg    = colors.white,
    text        = colors.black,
    textDim     = colors.gray,
    textMuted   = colors.lightGray,
    windowBg    = colors.white,
    titleBar    = colors.blue,
    titleBarFg  = colors.white,
    desktop     = colors.black,
    desktopFg   = colors.white,
    border      = colors.gray,
}

local state = {
    windows = {},
    nextWindowID = 1,
    activeWindow = nil,
    menuOpen = false,
    clock = "00:00",
    running = false,
    dragging = nil,
    desktopIcons = {
        { name = "Home",      icon = "H", color = colors.yellow, action = "/usr/bin/browser.lua", x = 2, y = 3 },
        { name = "Terminal",  icon = "T", color = colors.green, action = "/bin/sh.lua", x = 2, y = 7 },
        { name = "Editor",    icon = "E", color = colors.cyan, action = "/usr/bin/editor.lua", x = 2, y = 11 },
        { name = "Trash",     icon = "X", color = colors.gray, action = nil, x = 2, y = 15 },
    },
    contextMenu = nil,
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

-- Draw top panel
local function drawPanel()
    local w, h = term.getSize()
    fillRow(1, PALETTE.panel)
    -- Menu button
    writeAt(1, 1, " [Menu] ", PALETTE.panel, PALETTE.accent)
    -- Separator
    writeAt(9, 1, "|", PALETTE.panel, PALETTE.textDim)
    -- Window tasks
    local x = 11
    for _, win in ipairs(state.windows) do
        local label = win.title:sub(1, 12)
        local bg = (win == state.activeWindow) and PALETTE.accent or PALETTE.panel
        local fg = (win == state.activeWindow) and PALETTE.accentFg or PALETTE.text
        writeAt(x, 1, " " .. label .. " ", bg, fg)
        x = x + #label + 2
        if x > w - 20 then break end
    end
    -- System tray + clock (right)
    local info = state.clock .. " |"  -- separator + clock
    writeAt(w - #info + 1, 1, info, PALETTE.panel, PALETTE.text)
end

-- Draw desktop icons
local function drawDesktopIcons()
    for _, icon in ipairs(state.desktopIcons) do
        drawBox(icon.x, icon.y, 4, 3, icon.color)
        writeAt(icon.x + 1, icon.y + 1, icon.icon, icon.color, colors.black)
        writeAt(icon.x, icon.y + 3, icon.name:sub(1, 5), PALETTE.desktop, PALETTE.desktopFg)
    end
end

-- Draw a window
local function drawWindow(win)
    -- Window background
    drawBox(win.x, win.y, win.width, win.height, PALETTE.windowBg)
    -- Title bar
    local titleBg = (win == state.activeWindow) and PALETTE.titleBar or PALETTE.border
    drawBox(win.x, win.y, win.width, 1, titleBg)
    writeAt(win.x + 1, win.y, " " .. win.title:sub(1, win.width - 5) .. " ", titleBg, PALETTE.titleBarFg)
    -- Close button
    writeAt(win.x + win.width - 2, win.y, " X ", titleBg, colors.white)
    -- Window border
    term.setTextColor(PALETTE.border)
    term.setBackgroundColor(PALETTE.windowBg)
    -- Left/right borders
    for row = win.y + 1, win.y + win.height - 1 do
        term.setCursorPos(win.x, row); term.write("|")
        term.setCursorPos(win.x + win.width - 1, row); term.write("|")
    end
    -- Bottom border
    term.setCursorPos(win.x, win.y + win.height - 1)
    term.write("+" .. string.rep("-", win.width - 2) .. "+")
    -- Content
    if win.content then
        local lineY = win.y + 2
        for line in win.content:gmatch("[^\n]*") do
            if lineY >= win.y + win.height - 1 then break end
            writeAt(win.x + 1, lineY, line:sub(1, win.width - 2), PALETTE.windowBg, PALETTE.text)
            lineY = lineY + 1
        end
    end
end

-- Draw menu (application launcher)
local function drawMenu()
    local w, h = term.getSize()
    local menuW = 24
    local menuH = 16
    local x = 1
    local y = 2

    drawBox(1, 2, menuW, menuH, PALETTE.windowBg)
    -- Border
    term.setTextColor(PALETTE.border)
    term.setBackgroundColor(PALETTE.windowBg)
    term.setCursorPos(1, 2); term.write("+" .. string.rep("-", menuW - 2) .. "+")
    term.setCursorPos(1, 2 + menuH - 1); term.write("+" .. string.rep("-", menuW - 2) .. "+")
    -- Header
    writeAt(2, 3, "XFCE Applications", PALETTE.windowBg, PALETTE.accent)
    writeAt(2, 4, string.rep("-", menuW - 4), PALETTE.windowBg, PALETTE.textDim)
    -- App items
    local apps = {
        { name = "Terminal",       action = "/bin/sh.lua" },
        { name = "Text Editor",    action = "/usr/bin/editor.lua" },
        { name = "Files (text)",   action = "/usr/bin/browser.lua" },
        { name = "Files (GUI)",    action = "/usr/bin/gbrowse.lua" },
        { name = "Settings",       action = "/usr/bin/settings.lua" },
        { name = "Notes",          action = "/usr/bin/notes.lua" },
        { name = "Paint",          action = "/usr/bin/paint.lua" },
        { name = "Calculator",     action = "/usr/bin/calculator.lua" },
        { name = "Music Player",    action = "/usr/bin/player.lua" },
        { name = "System Info",    action = "/usr/bin/neofetch.lua" },
        { name = "Lua REPL",       action = "/usr/bin/lua-repl.lua" },
        { name = "Task Manager",   action = "/usr/bin/taskmgr.lua" },
        { name = "System Manager",  action = "/usr/bin/sysmgr.lua" },
        { name = "Redstone Panel", action = "/usr/bin/redstone-panel.lua" },
    }
    for i, app in ipairs(apps) do
        writeAt(2, 4 + i, app.name, PALETTE.windowBg, PALETTE.text)
    end
    -- Footer
    writeAt(2, 2 + menuH - 2, "ESC to close", PALETTE.windowBg, PALETTE.textDim)
end

-- Draw context menu
local function drawContextMenu()
    if not state.contextMenu then return end
    local cm = state.contextMenu
    local menuW = 22
    local menuH = #cm.items + 2
    drawBox(cm.x, cm.y, menuW, menuH, PALETTE.windowBg)
    writeAt(cm.x + 1, cm.y, "Context Menu", PALETTE.windowBg, PALETTE.accent)
    for i, item in ipairs(cm.items) do
        writeAt(cm.x + 1, cm.y + 1 + i, item.label:sub(1, menuW - 2), PALETTE.windowBg, PALETTE.text)
    end
end

-- Render
local function render()
    term.setBackgroundColor(PALETTE.desktop)
    term.clear()
    drawDesktopIcons()
    for _, win in ipairs(state.windows) do
        drawWindow(win)
    end
    if state.menuOpen then drawMenu() end
    drawContextMenu()
    drawPanel()
end

local function updateClock()
    state.clock = os.date("%H:%M")
end

local function openWindow(title, content, width, height)
    local w, h = term.getSize()
    local win = {
        id = state.nextWindowID,
        title = title,
        content = content or "",
        x = 10 + (state.nextWindowID - 1) * 2,
        y = 3 + (state.nextWindowID - 1) * 1,
        width = width or 30,
        height = height or 10,
    }
    state.nextWindowID = state.nextWindowID + 1
    win.x = math.max(2, math.min(w - win.width, win.x))
    win.y = math.max(2, math.min(h - win.height - 1, win.y))
    table.insert(state.windows, win)
    state.activeWindow = win
    return win
end

local function launchApp(path)
    if not fs.exists(path) then
        openWindow("Error", "Application not found:\n" .. path, 30, 5)
        return
    end
    local Kernel = _G.Kernel
    if Kernel then
        local pid = Kernel.exec(path, {})
        if pid then Kernel.wait(pid) end
    end
end

local function findWindowAt(x, y)
    for i = #state.windows, 1, -1 do
        local win = state.windows[i]
        if x >= win.x and x < win.x + win.width and y >= win.y and y < win.y + win.height then
            return win, i
        end
    end
    return nil
end

local function mainLoop()
    state.running = true
    updateClock()
    local clockTimer = os.startTimer(30)

    while state.running do
        render()
        local event = { os.pullEvent() }

        if event[1] == "timer" and event[2] == clockTimer then
            updateClock()
            clockTimer = os.startTimer(30)
        elseif event[1] == "key" then
            local key = event[2]
            if key == keys.escape then
                state.menuOpen = false
                state.contextMenu = nil
            elseif key == keys.q then
                state.running = false
            end
        elseif event[1] == "mouse_click" then
            local button, x, y = event[2], event[3], event[4]
            local w, h = term.getSize()

            if state.menuOpen then
                -- Click on menu item
                if x >= 1 and x <= 24 and y >= 5 and y <= 18 then
                    local apps = {
                        "/bin/sh.lua", "/usr/bin/editor.lua", "/usr/bin/browser.lua",
                        "/usr/bin/gbrowse.lua", "/usr/bin/settings.lua", "/usr/bin/notes.lua",
                        "/usr/bin/paint.lua", "/usr/bin/calculator.lua", "/usr/bin/player.lua",
                        "/usr/bin/neofetch.lua", "/usr/bin/lua-repl.lua", "/usr/bin/taskmgr.lua",
                        "/usr/bin/sysmgr.lua", "/usr/bin/redstone-panel.lua",
                    }
                    local idx = y - 4
                    if apps[idx] then
                        state.menuOpen = false
                        launchApp(apps[idx])
                    end
                else
                    state.menuOpen = false
                end
            elseif state.contextMenu then
                local cm = state.contextMenu
                local menuW = 22
                if x >= cm.x and x < cm.x + menuW and y > cm.y and y <= cm.y + #cm.items + 1 then
                    local idx = y - cm.y - 1
                    if cm.items[idx] then
                        cm.items[idx].action()
                    end
                end
                state.contextMenu = nil
            elseif y == 1 then
                -- Panel click
                if x <= 8 then
                    state.menuOpen = not state.menuOpen
                elseif x >= 10 then
                    -- Click on window task - activate that window
                    local taskX = 11
                    for _, win in ipairs(state.windows) do
                        local label = win.title:sub(1, 12)
                        if x >= taskX and x < taskX + #label + 2 then
                            state.activeWindow = win
                            break
                        end
                        taskX = taskX + #label + 2
                    end
                end
            else
                -- Desktop click
                local win, winIdx = findWindowAt(x, y)
                if win then
                    state.activeWindow = win
                    if y == win.y then
                        -- Title bar click
                        if x >= win.x + win.width - 3 then
                            -- Close button
                            table.remove(state.windows, winIdx)
                            state.activeWindow = state.windows[#state.windows] or nil
                        else
                            -- Start dragging
                            state.dragging = { window = win, offsetX = x - win.x, offsetY = y - win.y }
                        end
                    end
                else
                    -- Click on desktop icon?
                    local found = false
                    for _, icon in ipairs(state.desktopIcons) do
                        if x >= icon.x and x <= icon.x + 3 and y >= icon.y and y <= icon.y + 2 then
                            if icon.action then launchApp(icon.action) end
                            found = true
                            break
                        end
                    end
                    if not found and button == 2 then
                        -- Right click - context menu
                        state.contextMenu = {
                            x = x, y = y,
                            items = {
                                { label = "Open Terminal", action = function() launchApp("/bin/sh.lua") end },
                                { label = "Open Files",    action = function() launchApp("/usr/bin/browser.lua") end },
                                { label = "Settings",      action = function() launchApp("/usr/bin/settings.lua") end },
                                { label = "Logout",        action = function() state.running = false end },
                            }
                        }
                    end
                end
            end
        elseif event[1] == "mouse_drag" then
            if state.dragging then
                local win = state.dragging.window
                local newX = event[3] - state.dragging.offsetX
                local newY = event[4] - state.dragging.offsetY
                local w, h = term.getSize()
                win.x = math.max(1, math.min(w - win.width, newX))
                win.y = math.max(2, math.min(h - win.height, newY))
            end
        elseif event[1] == "mouse_up" then
            state.dragging = nil
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
    openWindow("Welcome to XFCE",
        "  ArchOS-CC XFCE Desktop\n\n" ..
        "  Click [Menu] for applications\n" ..
        "  Right-click for context menu\n" ..
        "  Drag windows by title bar\n" ..
        "  Press 'q' to logout",
        36, 9)

    mainLoop()

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    return 0
end

return main()
