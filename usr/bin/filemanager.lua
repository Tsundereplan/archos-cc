--[[
    usr/bin/filemanager.lua  —  GUI File Manager
    =============================================
    A two-pane graphical file manager like Midnight Commander or Norton Commander.
    Features:
      * Two panes side-by-side
      * File icons (different colors for folders, .lua, .nfp, etc.)
      * Function keys: F2 rename, F5 copy, F6 move, F8 delete
      * Tab to switch panes
      * Enter to open file in editor or cd into directory
      * '..' entry to go up
]]

local function setColor(c)
    if c and term.isColor() then term.setTextColor(c) end
end

local function setBG(c)
    if c and term.isColor() then term.setBackgroundColor(c) end
end

local function resetColors()
    setBG(colors.black)
    setColor(colors.white)
end

-- State
local state = {
    left = { path = "/", selected = 1, scroll = 1 },
    right = { path = "/", selected = 1, scroll = 1 },
    active = "left",
    showHidden = false,
    running = true,
}

-- Get color for a file based on type/extension
local function fileColor(name, isDir)
    if isDir then return colors.lightBlue end
    if name:match("%.lua$") then return colors.green end
    if name:match("%.nfp$") or name:match("%.blp$") then return colors.magenta end
    if name:match("%.md$") or name:match("%.txt$") then return colors.white end
    if name:match("%.db$") or name:match("%.service$") then return colors.yellow end
    return colors.lightGray
end

local function listDir(path)
    local items = {}
    if path ~= "/" then
        table.insert(items, { name = "..", isDir = true, parent = true })
    end
    if fs.exists(path) and fs.isDir(path) then
        local list = fs.list(path)
        table.sort(list)
        for _, name in ipairs(list) do
            if state.showHidden or name:sub(1, 1) ~= "." then
                table.insert(items, {
                    name = name,
                    isDir = fs.isDir(path .. "/" .. name),
                    parent = false,
                })
            end
        end
    end
    return items
end

local function drawPane(side, x, y, w, h)
    local pane = state[side]
    local items = listDir(pane.path)

    -- Border
    setColor(side == state.active and colors.yellow or colors.gray)
    term.setCursorPos(x, y)
    term.write("+" .. string.rep("-", w - 2) .. "+")
    for row = 1, h - 2 do
        term.setCursorPos(x, y + row)
        term.write("|" .. string.rep(" ", w - 2) .. "|")
    end
    term.setCursorPos(x, y + h - 1)
    term.write("+" .. string.rep("-", w - 2) .. "+")

    -- Path header
    setColor(colors.cyan)
    term.setCursorPos(x + 1, y)
    local pathDisplay = pane.path
    if #pathDisplay > w - 2 then pathDisplay = "..." .. pathDisplay:sub(-(w - 5)) end
    term.write(" " .. pathDisplay .. " ")

    -- Items
    for i = 1, h - 2 do
        local itemIdx = pane.scroll + i - 1
        local item = items[itemIdx]
        if item then
            local row = y + i
            term.setCursorPos(x + 1, row)
            -- Selected item: inverted colors
            if itemIdx == pane.selected then
                setBG(colors.white)
                setColor(colors.black)
            else
                setBG(colors.black)
                setColor(fileColor(item.name, item.isDir))
            end
            local name = item.name
            if item.isDir then name = name .. "/" end
            if #name > w - 4 then name = name:sub(1, w - 5) .. "~" end
            term.write(" " .. name .. string.rep(" ", w - 3 - #name))
        end
    end
    resetColors()
end

local function drawFunctionBar()
    local w, h = term.getSize()
    setColor(colors.black)
    setBG(colors.lightGray)
    term.setCursorPos(1, h)
    local bar = " F2:Rename  F5:Copy  F6:Move  F8:Delete  Tab:Switch  Q:Quit "
    if #bar > w then bar = bar:sub(1, w) end
    term.write(bar .. string.rep(" ", w - #bar))
    resetColors()
end

local function drawTitle()
    setColor(colors.lightBlue)
    term.setCursorPos(1, 1)
    print("ArchOS-CC File Manager")
    setColor(colors.white)
end

local function getActivePane()
    return state[state.active]
end

local function getActiveItems()
    return listDir(getActivePane().path)
end

-- Actions
local function cd(newDir)
    local pane = getActivePane()
    pane.path = newDir
    pane.selected = 1
    pane.scroll = 1
end

local function openItem()
    local pane = getActivePane()
    local items = getActiveItems()
    local item = items[pane.selected]
    if not item then return end
    if item.parent then
        -- Go up
        if pane.path ~= "/" then
            local parent = pane.path:match("^(.*)/[^/]+$") or "/"
            if parent == "" then parent = "/" end
            cd(parent)
        end
    elseif item.isDir then
        -- Enter directory
        local newPath = pane.path
        if newPath:sub(-1) ~= "/" then newPath = newPath .. "/" end
        cd(newPath .. item.name)
    else
        -- Open file in editor
        local filePath = pane.path
        if filePath:sub(-1) ~= "/" then filePath = filePath .. "/" end
        filePath = filePath .. item.name
        if _G.Kernel then
            local pid = _G.Kernel.exec("/usr/bin/editor.lua", {filePath})
            if pid then _G.Kernel.wait(pid) end
        else
            os.run(_G, "/usr/bin/editor.lua", filePath)
        end
    end
end

local function deleteItem()
    local pane = getActivePane()
    local items = getActiveItems()
    local item = items[pane.selected]
    if not item or item.parent then return end
    local filePath = pane.path
    if filePath:sub(-1) ~= "/" then filePath = filePath .. "/" end
    filePath = filePath .. item.name
    setColor(colors.red)
    term.setCursorPos(1, 3)
    print("Delete " .. item.name .. "? [y/N] ")
    setColor(colors.white)
    local c = read()
    if c and c:lower() == "y" then
        fs.delete(filePath)
    end
end

local function copyOrMove(action)
    local pane = getActivePane()
    local items = getActiveItems()
    local item = items[pane.selected]
    if not item or item.parent then return end
    local srcPath = pane.path
    if srcPath:sub(-1) ~= "/" then srcPath = srcPath .. "/" end
    srcPath = srcPath .. item.name

    -- Determine destination pane
    local dstSide = state.active == "left" and "right" or "left"
    local dstPane = state[dstSide]
    local dstPath = dstPane.path
    if dstPath:sub(-1) ~= "/" then dstPath = dstPath .. "/" end
    dstPath = dstPath .. item.name

    setColor(colors.yellow)
    term.setCursorPos(1, 3)
    print(action .. " " .. item.name .. " to " .. dstPane.path .. "? [y/N] ")
    setColor(colors.white)
    local c = read()
    if c and c:lower() == "y" then
        if action == "Copy" then
            fs.copy(srcPath, dstPath)
        else
            fs.move(srcPath, dstPath)
        end
    end
end

local function renameItem()
    local pane = getActivePane()
    local items = getActiveItems()
    local item = items[pane.selected]
    if not item or item.parent then return end
    setColor(colors.yellow)
    term.setCursorPos(1, 3)
    term.write("New name: ")
    setColor(colors.white)
    local newName = read()
    if newName and newName ~= "" then
        local oldPath = pane.path
        if oldPath:sub(-1) ~= "/" then oldPath = oldPath .. "/" end
        fs.move(oldPath .. item.name, oldPath .. newName)
    end
end

local function main()
    term.setBackgroundColor(colors.black)
    term.clear()

    while state.running do
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)
        drawTitle()

        local w, h = term.getSize()
        local paneW = math.floor((w - 1) / 2)
        local paneH = h - 4

        drawPane("left", 1, 3, paneW, paneH)
        drawPane("right", paneW + 2, 3, w - paneW - 1, paneH)
        drawFunctionBar()

        -- Status bar (line 2)
        setColor(colors.gray)
        term.setCursorPos(1, 2)
        local pane = getActivePane()
        local items = getActiveItems()
        local item = items[pane.selected]
        if item then
            local info = item.name
            if not item.isDir and not item.parent then
                local p = pane.path
                if p:sub(-1) ~= "/" then p = p .. "/" end
                info = info .. "  (" .. fs.getSize(p .. item.name) .. " B)"
            end
            term.write(" " .. state.active .. ": " .. info)
        end
        setColor(colors.white)

        local event = {os.pullEvent()}
        if event[1] == "key" then
            local pane = getActivePane()
            local items = getActiveItems()
            local maxSel = #items
            if event[2] == keys.up then
                pane.selected = pane.selected - 1
                if pane.selected < 1 then pane.selected = maxSel end
            elseif event[2] == keys.down then
                pane.selected = pane.selected + 1
                if pane.selected > maxSel then pane.selected = 1 end
            elseif event[2] == keys.tab then
                state.active = state.active == "left" and "right" or "left"
            elseif event[2] == keys.enter then
                openItem()
            elseif event[2] == keys.q then
                state.running = false
            elseif event[2] == keys.h then
                state.showHidden = not state.showHidden
            elseif event[2] == keys.f2 then
                renameItem()
            elseif event[2] == keys.f5 then
                copyOrMove("Copy")
            elseif event[2] == keys.f6 then
                copyOrMove("Move")
            elseif event[2] == keys.f8 then
                deleteItem()
            elseif event[2] == keys.leftCtrl or event[2] == keys.rightCtrl then
                -- modifier
            end
        end

        -- Adjust scroll if needed
        local pane = getActivePane()
        local items = getActiveItems()
        local paneH = h - 4
        if pane.selected < pane.scroll then pane.scroll = pane.selected end
        if pane.selected >= pane.scroll + paneH - 2 then
            pane.scroll = pane.selected - paneH + 3
        end
    end

    resetColors()
    term.clear()
    term.setCursorPos(1, 1)
    return 0
end

return main()
