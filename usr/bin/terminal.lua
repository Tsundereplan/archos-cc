--[[
    usr/bin/terminal.lua  —  Multi-tab Terminal Emulator
    ==================================================
    Like xterm/urxvt but in CC:Tweaked. Features:
      * Multiple tabs (up to 5)
      * Each tab runs a separate shell
      * Bottom tab bar shows open tabs
      * Ctrl+T opens new tab
      * Ctrl+W closes current tab
      * Alt+1..9 switches tabs
]]

local function setColor(c)
    if c and term.isColor() then pcall(function() term.setTextColor(c) end) end
end

local function setBG(c)
    if c and term.isColor() then pcall(function() term.setBackgroundColor(c) end) end
end

local state = {
    tabs = {},
    activeTab = 1,
    running = true,
}

local function createTab()
    local tab = {
        title = "shell",
        pid = nil,
        -- Save initial state for this tab
    }
    return tab
end

local function drawTabBar()
    local w, h = term.getSize()
    setBG(colors.blue)
    setColor(colors.white)
    term.setCursorPos(1, 1)
    for i, tab in ipairs(state.tabs) do
        if i == state.activeTab then
            setBG(colors.white)
            setColor(colors.black)
        else
            setBG(colors.blue)
            setColor(colors.white)
        end
        term.write(" " .. i .. ":" .. tab.title .. " ")
    end
    -- Fill rest with blue
    setBG(colors.blue)
    setColor(colors.white)
    local usedX = 1
    for _, tab in ipairs(state.tabs) do
        usedX = usedX + #tab.title + 3
    end
    if usedX < w then
        term.write(string.rep(" ", w - usedX + 1))
    end
    setBG(colors.black)
end

local function main()
    -- Start with one tab
    if not _G.Kernel then
        print("Terminal requires kernel (Kernel API)")
        return 1
    end

    -- Create first tab
    local tab = createTab()
    tab.pid = _G.Kernel.exec("/bin/sh.lua", {})
    table.insert(state.tabs, tab)

    while state.running do
        drawTabBar()

        -- Wait for events
        local event = {os.pullEvent()}

        if event[1] == "key" then
            local key = event[2]
            if key == keys.leftCtrl or key == keys.rightCtrl then
                -- Wait for next key
                local e2 = {os.pullEvent("key")}
                if e2[2] == keys.t then
                    -- New tab
                    if #state.tabs < 5 then
                        local newTab = createTab()
                        newTab.pid = _G.Kernel.exec("/bin/sh.lua", {})
                        table.insert(state.tabs, newTab)
                        state.activeTab = #state.tabs
                    end
                elseif e2[2] == keys.w then
                    -- Close tab
                    if #state.tabs > 1 then
                        local tab = state.tabs[state.activeTab]
                        if tab.pid then
                            _G.Kernel.kill(tab.pid)
                        end
                        table.remove(state.tabs, state.activeTab)
                        if state.activeTab > #state.tabs then
                            state.activeTab = #state.tabs
                        end
                    else
                        state.running = false
                    end
                end
            elseif key == keys.leftAlt or key == keys.rightAlt then
                -- Alt+number
                local e2 = {os.pullEvent("char")}
                local n = tonumber(e2[2])
                if n and n >= 1 and n <= #state.tabs then
                    state.activeTab = n
                end
            end
        end
    end

    -- Clean up: kill all tab shells
    for _, tab in ipairs(state.tabs) do
        if tab.pid then
            _G.Kernel.kill(tab.pid)
        end
    end

    setBG(colors.black)
    setColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    return 0
end

return main()
