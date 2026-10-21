--[[
    de/gui.lua  —  Unified ArchOS-CC Desktop Environment
    ====================================================
    A single, modern graphical desktop environment that replaces
    the old tty/gnome/plasma/xfce trio. Reads the application
    list from /etc/apps.conf so you can add/remove apps without
    touching any Lua code.

    Features:
      * Top menu bar with: ArchOS menu, Apps, System, Clock
      * Desktop with clickable icons (auto-generated from apps.conf)
      * Application windows with title bars, close button, drag
      * Right-click desktop for context menu
      * Alt+Tab to switch between running apps
      * F1 = Run command (KRunner-like)
      * Apps are launched via Kernel.exec / os.run

    apps.conf format (one app per line):
        name|path|icon|color
      Where:
        name  = display name (e.g. "Text Editor")
        path  = full path to .lua file (e.g. /usr/bin/editor.lua)
        icon  = single character or short label (e.g. "E" or "EDIT")
        color = CC:T color name (e.g. green, lightBlue, magenta)
      Lines starting with # are comments.

    Setting as default DE:
        echo "gui" > /etc/default-de
]]

-- ============================================================
--  Configuration
-- ============================================================

local APPS_CONF = "/etc/apps.conf"

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

-- Map color name -> colors.X
local COLOR_MAP = {
    white=colors.white, orange=colors.orange, magenta=colors.magenta,
    lightBlue=colors.lightBlue, yellow=colors.yellow, lime=colors.lime,
    pink=colors.pink, gray=colors.gray, lightGray=colors.lightGray,
    cyan=colors.cyan, purple=colors.purple, blue=colors.blue,
    brown=colors.brown, green=colors.green, red=colors.red, black=colors.black,
}
local function colorFromName(name)
    if not name then return colors.lightGray end
    return COLOR_MAP[name] or colors.lightGray
end

-- Write text at position with colors
local function writeAt(x, y, text, bg, fg)
    if bg then setBG(bg) end
    if fg then setColor(fg) end
    term.setCursorPos(x, y)
    term.write(text)
    reset()
end

-- Draw filled box
local function box(x, y, w, h, color)
    setBG(color)
    for row = y, y + h - 1 do
        term.setCursorPos(x, row)
        term.write(string.rep(" ", w))
    end
    reset()
end

-- ============================================================
--  Load apps from /etc/apps.conf
-- ============================================================

local function loadApps()
    local apps = {}
    if not fs.exists(APPS_CONF) then
        -- Fallback: hard-coded default apps
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
    local f = fs.open(APPS_CONF, "r")
    if not f then return {} end
    for line in f.readLine do
        if line and line ~= "" and line:sub(1, 1) ~= "#" then
            -- Parse: name|path|icon|color
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
--  State
-- ============================================================

local state = {
    apps = {},
    windows = {},        -- open windows (running apps)
    nextWindowID = 1,
    activeWindow = nil,
    menuOpen = nil,     -- "archos" | "apps" | "system" | nil
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
    -- Top bar
    box(1, 1, w, 1, colors.blue)
    setColor(colors.white)
    -- Left: ArchOS menu + Apps menu
    writeAt(2, 1, "ArchOS", colors.blue, state.menuOpen == "archos" and colors.yellow or colors.white)
    writeAt(9, 1, "Apps",   colors.blue, state.menuOpen == "apps" and colors.yellow or colors.white)
    writeAt(14, 1, "System", colors.blue, state.menuOpen == "system" and colors.yellow or colors.white)
    -- Center: title
    writeAt(math.floor(w/2) - 4, 1, "ArchOS-CC", colors.blue, colors.white)
    -- Right: clock
    writeAt(w - #state.clock - 1, 1, state.clock, colors.blue, colors.white)
    reset()
end

local function drawDesktopIcons()
    -- Draw icons in a vertical column on the left side
    local apps = state.apps
    for i, app in ipairs(apps) do
        local x = 2
        local y = 3 + (i - 1) * 4
        local w, h = term.getSize()
        if y + 3 > h - 1 then break end
        -- Icon box
        box(x, y, 4, 3, app.color)
        writeAt(x + 1, y + 1, " " .. (app.icon or "?") .. " ", app.color, colors.black)
        -- Label below
        local label = app.name
        if #label > 6 then label = label:sub(1, 6) end
        writeAt(x, y + 3, " " .. label .. "  ", colors.black, colors.white)
    end
end

local function drawWindow(win)
    -- Shadow
    local w, h = term.getSize()
    if win.x + win.width < w then
        box(win.x + 1, win.y + 1, win.width, win.height, colors.gray)
    end
    -- Window background
    box(win.x, win.y, win.width, win.height, colors.black)
    -- Title bar (highlight if active)
    local titleBG = (win == state.activeWindow) and colors.blue or colors.gray
    box(win.x, win.y, win.width, 1, titleBG)
    writeAt(win.x + 1, win.y, " " .. win.title:sub(1, win.width - 4) .. " ", titleBG, colors.white)
    -- Close button
    writeAt(win.x + win.width - 1, win.y, "X", titleBG, colors.yellow)
    -- Content (if any)
    if win.content then
        local lineY = win.y + 2
        for line in (win.content or ""):gmatch("[^\n]*") do
            if lineY >= win.y + win.height then break end
            writeAt(win.x + 1, lineY, line:sub(1, win.width - 2), colors.black, colors.white)
            lineY = lineY + 1
        end
    end
end

local function drawMenu(menuType)
    local w, h = term.getSize()
    local items
    local title
    if menuType == "archos" then
        title = "ArchOS"
        items = {
            { label = "About ArchOS-CC", action = function()
                state.windows[#state.windows + 1] = {
                    id = state.nextWindowID, title = "About",
                    content = "ArchOS-CC v" .. (_G.ARCHOS_VERSION or "1.3.6") .. "\n\n" ..
                              "Unified GUI Desktop\n\n" ..
                              "Press F1 for Run dialog\n" ..
                              "Right-click desktop for menu\n" ..
                              "Press 'q' to logout",
                    x = 10, y = 5, width = 30, height = 10,
                }
                state.nextWindowID = state.nextWindowID + 1
                state.activeWindow = state.windows[#state.windows]
            end },
            { label = "Run... (F1)", action = function()
                state.runDialogOpen = true
                state.runQuery = ""
            end },
            { label = "Logout", action = function()
                state.running = false
            end },
            { label = "Reboot", action = function()
                os.reboot()
            end },
            { label = "Power Off", action = function()
                os.shutdown()
            end },
        }
    elseif menuType == "apps" then
        title = "Applications"
        items = {}
        for _, app in ipairs(state.apps) do
            table.insert(items, {
                label = app.name,
                action = function()
                    -- Launch the app
                    if _G.Kernel then
                        local pid = _G.Kernel.exec(app.path, {})
                        if pid then _G.Kernel.wait(pid) end
                    else
                        os.run(_G, app.path)
                    end
                end,
            })
        end
    elseif menuType == "system" then
        title = "System"
        items = {
            { label = "Settings", action = function()
                if _G.Kernel then
                    local pid = _G.Kernel.exec("/usr/bin/settings.lua", {})
                    if pid then _G.Kernel.wait(pid) end
                end
            end },
            { label = "System Monitor", action = function()
                if _G.Kernel then
                    local pid = _G.Kernel.exec("/usr/bin/system-monitor.lua", {})
                    if pid then _G.Kernel.wait(pid) end
                end
            end },
            { label = "Task Manager", action = function()
                if _G.Kernel then
                    local pid = _G.Kernel.exec("/usr/bin/taskmgr.lua", {})
                    if pid then _G.Kernel.wait(pid) end
                end
            end },
            { label = "Update", action = function()
                if _G.Kernel then
                    local pid = _G.Kernel.exec("/bin/update.lua", {"check"})
                    if pid then _G.Kernel.wait(pid) end
                end
            end },
            { label = "Cleanup", action = function()
                if _G.Kernel then
                    local pid = _G.Kernel.exec("/bin/cleanup.lua", {"--force"})
                    if pid then _G.Kernel.wait(pid) end
                end
            end },
        }
    end
    -- Draw dropdown menu
    local menuW = 28
    local menuH = #items + 2
    local x = 1
    if menuType == "archos" then x = 1
    elseif menuType == "apps" then x = 8
    elseif menuType == "system" then x = 13 end
    local y = 2
    box(x, y, menuW, menuH, colors.lightGray)
    setColor(colors.black); setBG(colors.lightGray)
    term.setCursorPos(x + 1, y)
    term.write(" " .. title .. " ")
    for i, item in ipairs(items) do
        local label = item.label
        if #label > menuW - 4 then label = label:sub(1, menuW - 4) end
        writeAt(x + 1, y + i, " " .. label .. string.rep(" ", menuW - #label - 3), colors.lightGray, colors.black)
    end
    reset()
    return items, x, y, menuW, menuH
end

local function drawRunDialog()
    local w, h = term.getSize()
    local boxW = 40
    local boxH = 3
    local x = math.floor((w - boxW) / 2)
    local y = math.floor(h / 2) - 1
    box(x + 1, y + 1, boxW, boxH, colors.gray)  -- shadow
    box(x, y, boxW, boxH, colors.blue)
    writeAt(x + 1, y, " Run command: ", colors.blue, colors.yellow)
    writeAt(x + 1, y + 1, " > " .. state.runQuery .. "_", colors.blue, colors.white)
    writeAt(x + 1, y + 2, " Press Enter to run, Esc to cancel ", colors.blue, colors.lightGray)
end

local function render()
    local w, h = term.getSize()
    -- Desktop background
    box(1, 1, w, h, colors.black)
    drawMenuBar()
    drawDesktopIcons()
    -- Windows
    for _, win in ipairs(state.windows) do
        drawWindow(win)
    end
    -- Menus
    if state.menuOpen then
        drawMenu(state.menuOpen)
    end
    -- Run dialog
    if state.runDialogOpen then
        drawRunDialog()
    end
end

-- ============================================================
--  Window management
-- ============================================================

local function findWindowAt(x, y)
    for i = #state.windows, 1, -1 do
        local win = state.windows[i]
        if x >= win.x and x < win.x + win.width and y >= win.y and y < win.y + win.height then
            return win, i
        end
    end
    return nil
end

local function closeWindow(win)
    for i, w in ipairs(state.windows) do
        if w == win then
            table.remove(state.windows, i)
            break
        end
    end
    state.activeWindow = state.windows[#state.windows] or nil
end

-- ============================================================
--  Main loop
-- ============================================================

local function main()
    state.apps = loadApps()
    state.clock = os.date("%H:%M")

    -- Run login first
    if fs.exists("/bin/login.lua") and _G.Kernel then
        local pid = _G.Kernel.exec("/bin/login.lua", {})
        if pid then _G.Kernel.wait(pid) end
    end

    -- Clock update timer
    local clockTimer = os.startTimer(30)

    -- Main event loop, wrapped in pcall for safety
    while state.running do
        local ok, err = pcall(function()
            render()
            local event = { os.pullEvent() }

            if event[1] == "timer" and event[2] == clockTimer then
                state.clock = os.date("%H:%M")
                clockTimer = os.startTimer(30)
            elseif event[1] == "key" then
                local key = event[2]
                if key == keys.f1 then
                    state.runDialogOpen = not state.runDialogOpen
                    state.runQuery = ""
                    state.menuOpen = nil
                elseif key == keys.escape then
                    state.menuOpen = nil
                    state.runDialogOpen = false
                    state.runQuery = ""
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
                    -- Try to launch
                    local path = q
                    if not path:match("^/") then
                        -- Search in /bin and /usr/bin
                        for _, d in ipairs({"/bin", "/usr/bin", "/sbin", "/usr/sbin"}) do
                            local p = d .. "/" .. q
                            if not p:match("%.lua$") then p = p .. ".lua" end
                            if fs.exists(p) then path = p; break end
                        end
                    end
                    if fs.exists(path) then
                        if _G.Kernel then
                            local pid = _G.Kernel.exec(path, {})
                            if pid then _G.Kernel.wait(pid) end
                        else
                            os.run(_G, path)
                        end
                    end
                elseif event[2] == keys.backspace then
                    state.runQuery = state.runQuery:sub(1, -2)
                end
            elseif event[1] == "mouse_click" then
                local button, x, y = event[2], event[3], event[4]
                local w, h = term.getSize()

                -- Click in menu bar
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
                elseif state.menuOpen then
                    -- Click on a menu item
                    local items, mx, my, mw, mh = drawMenu(state.menuOpen)
                    if x >= mx and x < mx + mw and y > my and y <= my + #items then
                        local item = items[y - my]
                        if item then
                            state.menuOpen = nil
                            item.action()
                        end
                    else
                        state.menuOpen = nil
                    end
                elseif y == h then
                    -- Bottom (no taskbar in this DE, ignore)
                else
                    -- Click on desktop - check windows first
                    local win = findWindowAt(x, y)
                    if win then
                        state.activeWindow = win
                        if y == win.y then
                            -- Title bar click
                            if x == win.x + win.width - 1 then
                                -- Close button
                                closeWindow(win)
                            else
                                -- Start dragging
                                state.dragging = { window = win, offsetX = x - win.x, offsetY = y - win.y }
                            end
                        end
                    else
                        -- Check desktop icons
                        for i, app in ipairs(state.apps) do
                            local ix = 2
                            local iy = 3 + (i - 1) * 4
                            if x >= ix and x <= ix + 3 and y >= iy and y <= iy + 2 then
                                -- Launch app
                                if _G.Kernel then
                                    local pid = _G.Kernel.exec(app.path, {})
                                    if pid then _G.Kernel.wait(pid) end
                                else
                                    os.run(_G, app.path)
                                end
                                break
                            end
                        end
                    end
                end
            elseif event[1] == "mouse_drag" then
                if state.dragging then
                    local win = state.dragging.window
                    local w, h = term.getSize()
                    win.x = math.max(1, math.min(w - win.width, event[3] - state.dragging.offsetX))
                    win.y = math.max(2, math.min(h - win.height, event[4] - state.dragging.offsetY))
                end
            elseif event[1] == "mouse_up" then
                state.dragging = nil
            end
        end)
        if not ok then
            -- Log error and continue
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
