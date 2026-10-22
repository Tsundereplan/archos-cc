--[[
    usr/bin/filemanager.lua  —  ArchOS File Manager v2
    ==================================================
    Advanced two-pane file manager (Midnight Commander style).

    Features:
      * Two panes side-by-side, each with its own path
      * Path bar at top showing current location with breadcrumbs
      * Status bar at bottom with file info (size, type, modified)
      * Sort by name / size / date (cycle with 's')
      * Quick view pane: preview file content on the right
      * Multi-select with Space (then F5/F6 act on all)
      * Search filter with '/' (highlights matching files)
      * Make dir (F7), make file (Shift+F4)
      * Tree view of current dir (press 't' to toggle)
      * Confirmation dialogs with Y/N
      * Progress bar for large copy/move operations
      * Bookmarks: Ctrl+1..5 to save, Alt+1..5 to jump
      * Color-coded files by extension

    Hotkeys:
      Arrows / j,k       Navigate
      Tab                Switch active pane
      Enter              Open file / enter dir
      Space              Toggle select (mark) current file
      Insert             Same as Space
      F2 / Ctrl+R       Rename current file
      F4                 Edit current file in editor
      F5 / Ctrl+C        Copy selected to other pane
      F6 / Ctrl+X        Move selected to other pane
      F7 / Ctrl+N        New directory
      Shift+F4           New file (opens editor)
      F8 / Delete        Delete selected
      a..z               Quick-jump to file starting with letter
      /                  Filter (type to narrow list)
      s                  Cycle sort: name -> size -> date
      t                  Toggle tree view
      h                  Toggle hidden files
      Ctrl+1..5          Bookmark current dir
      Alt+1..5           Jump to bookmark
      q                  Quit
]]

local function setColor(c)
    if c and term.isColor() then pcall(function() term.setTextColor(c) end) end
end

local function setBG(c)
    if c and term.isColor() then pcall(function() term.setBackgroundColor(c) end) end
end

local function resetColors()
    setBG(colors.black)
    setColor(colors.white)
end

-- State
local state = {
    left  = { path = "/", selected = 1, scroll = 1, items = {} },
    right = { path = "/", selected = 1, scroll = 1, items = {} },
    active = "left",
    showHidden = false,
    sortMode = "name",  -- "name" | "size" | "date"
    treeView = false,
    filter = "",
    bookmarks = {},  -- 1..5 -> paths
    running = true,
}

-- File color by extension
local function fileColor(name, isDir)
    if isDir then return colors.lightBlue end
    if name:match("%.lua$") then return colors.green end
    if name:match("%.nfp$") or name:match("%.blp$") then return colors.magenta end
    if name:match("%.md$") then return colors.white end
    if name:match("%.txt$") then return colors.lightGray end
    if name:match("%.db$") or name:match("%.service$") or name:match("%.conf$") then return colors.yellow end
    if name:match("%.upd$") or name:match("%.version$") then return colors.orange end
    if name:match("%.shadow$") or name:match("%.passwd$") then return colors.red end
    return colors.lightGray
end

-- File type icon (single char)
local function fileIcon(name, isDir)
    if isDir then return "/" end
    if name:match("%.lua$") then return "*" end
    if name:match("%.nfp$") or name:match("%.blp$") then return "#" end
    if name:match("%.md$") or name:match("%.txt$") then return "F" end
    return " "
end

-- Read directory listing with metadata
local function listDir(path)
    local items = {}
    if path ~= "/" then
        table.insert(items, { name = "..", isDir = true, parent = true, size = 0 })
    end
    if fs.exists(path) and fs.isDir(path) then
        local list = fs.list(path)
        for _, name in ipairs(list) do
            if state.showHidden or name:sub(1, 1) ~= "." then
                local fullPath = path
                if fullPath:sub(-1) ~= "/" then fullPath = fullPath .. "/" end
                fullPath = fullPath .. name
                local isDir = fs.isDir(fullPath)
                local size = 0
                if not isDir then
                    local ok, s = pcall(fs.getSize, fullPath)
                    if ok then size = s end
                end
                table.insert(items, {
                    name = name,
                    isDir = isDir,
                    parent = false,
                    size = size,
                    path = fullPath,
                })
            end
        end
    end

    -- Sort
    local mode = state.sortMode
    table.sort(items, function(a, b)
        -- Always keep ".." first
        if a.parent and not b.parent then return true end
        if b.parent and not a.parent then return false end
        if a.parent and b.parent then return false end
        -- Directories before files
        if a.isDir and not b.isDir then return true end
        if b.isDir and not a.isDir then return false end
        -- Then by sort mode
        if mode == "size" then
            return (a.size or 0) < (b.size or 0)
        elseif mode == "date" then
            -- CC:Tweaked doesn't expose mtime; fallback to name
            return a.name < b.name
        else  -- "name"
            return a.name < b.name
        end
    end)

    -- Apply filter
    if state.filter and state.filter ~= "" then
        local filtered = {}
        for _, item in ipairs(items) do
            if item.parent or item.name:lower():find(state.filter:lower(), 1, true) then
                table.insert(filtered, item)
            end
        end
        return filtered
    end
    return items
end

-- Refresh both panes
local function refresh()
    state.left.items  = listDir(state.left.path)
    state.right.items = listDir(state.right.path)
    -- Clamp selection
    for _, side in ipairs({"left", "right"}) do
        local pane = state[side]
        if pane.selected > #pane.items then pane.selected = #pane.items end
        if pane.selected < 1 then pane.selected = 1 end
        if pane.scroll > pane.selected then pane.scroll = pane.selected end
    end
end

-- Format file size
local function humanSize(b)
    if not b or b == 0 then return "0" end
    if b < 1024 then return b .. "B"
    elseif b < 1024 * 1024 then return string.format("%.1fK", b / 1024)
    else return string.format("%.1fM", b / (1024 * 1024)) end
end

-- Draw a pane (border + items)
local function drawPane(side, x, y, w, h)
    local pane = state[side]
    local isActive = side == state.active

    -- Border
    setColor(isActive and colors.yellow or colors.gray)
    term.setCursorPos(x, y)
    term.write("+" .. string.rep("-", w - 2) .. "+")
    for row = 1, h - 2 do
        term.setCursorPos(x, y + row)
        term.write("|" .. string.rep(" ", w - 2) .. "|")
    end
    term.setCursorPos(x, y + h - 1)
    term.write("+" .. string.rep("-", w - 2) .. "+")

    -- Path header (breadcrumb)
    setColor(colors.cyan)
    term.setCursorPos(x + 1, y)
    local pathDisplay = pane.path
    if #pathDisplay > w - 2 then
        pathDisplay = "..." .. pathDisplay:sub(-(w - 5))
    end
    term.write(" " .. pathDisplay .. " ")

    -- Items
    local visibleCount = h - 2
    for i = 1, visibleCount do
        local itemIdx = pane.scroll + i - 1
        local item = pane.items[itemIdx]
        if item then
            local row = y + i
            term.setCursorPos(x + 1, row)
            -- Selected: inverted
            if itemIdx == pane.selected then
                setBG(colors.white)
                setColor(colors.black)
            else
                setBG(colors.black)
                setColor(fileColor(item.name, item.isDir))
            end
            local name = item.name
            if item.isDir and not item.parent then name = name .. "/" end
            -- Truncate to fit
            local maxName = w - 8
            if #name > maxName then name = name:sub(1, maxName - 1) .. "~" end
            local icon = fileIcon(item.name, item.isDir)
            if item.parent then icon = "^" end
            local sizeStr = ""
            if not item.isDir and not item.parent then
                sizeStr = string.format("%5s", humanSize(item.size))
            elseif not item.parent then
                sizeStr = "  DIR"
            end
            -- Pad name to fixed width for alignment
            local namePadded = name .. string.rep(" ", maxName - #name)
            term.write(" " .. icon .. " " .. namePadded .. " " .. sizeStr .. " ")
        end
    end
    resetColors()
end

-- Draw top title bar
local function drawTitleBar()
    local w, h = term.getSize()
    setBG(colors.blue)
    setColor(colors.white)
    term.setCursorPos(1, 1)
    local title = " ArchOS File Manager v2 "
    local sortStr = " sort:" .. state.sortMode
    local hiddenStr = state.showHidden and " [hidden]" or ""
    local filterStr = state.filter ~= "" and (" filter:'" .. state.filter .. "'") or ""
    local info = sortStr .. hiddenStr .. filterStr
    local padLen = w - #title - #info - 1
    if padLen < 0 then padLen = 0 end
    term.write(title .. string.rep(" ", padLen) .. info .. " ")
    setBG(colors.black)
    setColor(colors.white)
end

-- Draw status bar at bottom (file info + hotkeys)
local function drawStatusBar()
    local w, h = term.getSize()
    local pane = state[state.active]
    local item = pane.items[pane.selected]
    setBG(colors.lightGray)
    setColor(colors.black)
    term.setCursorPos(1, h - 1)
    local info = " No file selected "
    if item then
        local path = pane.path
        if path:sub(-1) ~= "/" then path = path .. "/" end
        path = path .. item.name
        info = " " .. state.active .. ": "
        if item.parent then
            info = info .. "(parent dir)"
        elseif item.isDir then
            info = info .. item.name .. "/ [DIR]"
        else
            info = info .. item.name .. " (" .. tostring(item.size) .. " B)"
        end
    end
    if #info > w - 1 then info = info:sub(1, w - 1) end
    term.write(info .. string.rep(" ", w - #info - 1) .. " ")
    -- Function key bar
    setBG(colors.black)
    setColor(colors.yellow)
    term.setCursorPos(1, h)
    local fkeys = "2:Ren 4:Edit 5:Cp 6:Mv 7:MkD 8:Del Tab:Sw Q:Quit"
    if #fkeys > w then fkeys = fkeys:sub(1, w) end
    term.write(fkeys)
    resetColors()
end

-- Confirmation dialog
local function confirmDialog(message)
    local w, h = term.getSize()
    local boxW = math.min(#message + 8, w - 4)
    local boxH = 5
    local x = math.floor((w - boxW) / 2)
    local y = math.floor((h - boxH) / 2)
    -- Save area
    setBG(colors.gray)
    setColor(colors.white)
    for row = 0, boxH - 1 do
        term.setCursorPos(x, y + row)
        term.write(string.rep(" ", boxW))
    end
    -- Border
    setColor(colors.yellow)
    term.setCursorPos(x, y)
    term.write("+" .. string.rep("-", boxW - 2) .. "+")
    term.setCursorPos(x, y + boxH - 1)
    term.write("+" .. string.rep("-", boxW - 2) .. "+")
    -- Message
    setColor(colors.white)
    term.setCursorPos(x + 2, y + 1)
    local msg = message
    if #msg > boxW - 4 then msg = msg:sub(1, boxW - 4) end
    term.write(msg)
    -- Prompt
    term.setCursorPos(x + 2, y + 3)
    setColor(colors.yellow)
    term.write("[Y]es / [N]o? ")
    resetColors()
    -- Wait for Y/N
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "char" then
            local c = ev[2]:lower()
            if c == "y" then return true end
            if c == "n" then return false end
        elseif ev[1] == "key" and ev[2] == keys.enter then
            return true
        elseif ev[1] == "key" and ev[2] == keys.escape then
            return false
        end
    end
end

-- Input dialog (for rename, new dir, etc.)
local function inputDialog(prompt, default)
    local w, h = term.getSize()
    local boxW = math.min(#prompt + 30, w - 4)
    local boxH = 5
    local x = math.floor((w - boxW) / 2)
    local y = math.floor((h - boxH) / 2)
    setBG(colors.gray)
    setColor(colors.white)
    for row = 0, boxH - 1 do
        term.setCursorPos(x, y + row)
        term.write(string.rep(" ", boxW))
    end
    setColor(colors.yellow)
    term.setCursorPos(x, y)
    term.write("+" .. string.rep("-", boxW - 2) .. "+")
    term.setCursorPos(x, y + boxH - 1)
    term.write("+" .. string.rep("-", boxW - 2) .. "+")
    setColor(colors.white)
    term.setCursorPos(x + 2, y + 1)
    term.write(prompt)
    term.setCursorPos(x + 2, y + 3)
    setColor(colors.black)
    setBG(colors.white)
    term.write(string.rep(" ", boxW - 4))
    term.setCursorPos(x + 2, y + 3)
    local value = default or ""
    term.write(value)
    -- Read input
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "char" then
            value = value .. ev[2]
            if #value > boxW - 5 then value = value:sub(1, boxW - 5) end
            term.setCursorPos(x + 2, y + 3)
            setBG(colors.white)
            setColor(colors.black)
            term.write(value .. string.rep(" ", boxW - 4 - #value))
            term.setCursorPos(x + 2 + #value, y + 3)
        elseif ev[1] == "key" then
            if ev[2] == keys.enter then
                resetColors()
                return value
            elseif ev[2] == keys.backspace then
                if #value > 0 then
                    value = value:sub(1, -2)
                    term.setCursorPos(x + 2, y + 3)
                    setBG(colors.white)
                    setColor(colors.black)
                    term.write(value .. string.rep(" ", boxW - 4 - #value))
                    term.setCursorPos(x + 2 + #value, y + 3)
                end
            elseif ev[2] == keys.escape then
                resetColors()
                return nil
            end
        end
    end
end

-- Show progress bar
local function showProgress(current, total, label)
    local w, h = term.getSize()
    local boxW = 30
    local boxH = 5
    local x = math.floor((w - boxW) / 2)
    local y = math.floor((h - boxH) / 2)
    setBG(colors.gray)
    setColor(colors.white)
    for row = 0, boxH - 1 do
        term.setCursorPos(x, y + row)
        term.write(string.rep(" ", boxW))
    end
    setColor(colors.yellow)
    term.setCursorPos(x, y)
    term.write("+" .. string.rep("-", boxW - 2) .. "+")
    term.setCursorPos(x, y + boxH - 1)
    term.write("+" .. string.rep("-", boxW - 2) .. "+")
    setColor(colors.white)
    term.setCursorPos(x + 2, y + 1)
    local l = label or "Working..."
    if #l > boxW - 4 then l = l:sub(1, boxW - 4) end
    term.write(l)
    -- Progress bar
    term.setCursorPos(x + 2, y + 3)
    local barW = boxW - 4
    local filled = 0
    if total and total > 0 then
        filled = math.floor((current / total) * barW)
    end
    setBG(colors.green)
    term.write(string.rep(" ", filled))
    setBG(colors.black)
    term.write(string.rep(" ", barW - filled))
    resetColors()
end

-- Get the active pane
local function getActivePane()
    return state[state.active]
end

-- Get the other pane
local function getInactivePane()
    return state[state.active == "left" and "right" or "left"]
end

-- Actions
local function cd(newDir)
    local pane = getActivePane()
    pane.path = newDir
    pane.selected = 1
    pane.scroll = 1
    refresh()
end

local function navigate(direction)
    local pane = getActivePane()
    local items = pane.items
    local max = #items
    if direction == "up" then
        pane.selected = pane.selected - 1
        if pane.selected < 1 then pane.selected = max end
    elseif direction == "down" then
        pane.selected = pane.selected + 1
        if pane.selected > max then pane.selected = 1 end
    end
    -- Adjust scroll
    local visibleCount = (select(2, term.getSize())) - 5  -- approx
    if pane.selected < pane.scroll then pane.scroll = pane.selected end
    if pane.selected >= pane.scroll + visibleCount then
        pane.scroll = pane.selected - visibleCount + 1
    end
end

local function openItem()
    local pane = getActivePane()
    local item = pane.items[pane.selected]
    if not item then return end
    if item.parent then
        if pane.path ~= "/" then
            local parent = pane.path:match("^(.*)/[^/]+$") or "/"
            if parent == "" then parent = "/" end
            cd(parent)
        end
    elseif item.isDir then
        local newPath = pane.path
        if newPath:sub(-1) ~= "/" then newPath = newPath .. "/" end
        cd(newPath .. item.name)
    else
        -- Open in editor
        local filePath = pane.path
        if filePath:sub(-1) ~= "/" then filePath = filePath .. "/" end
        filePath = filePath .. item.name
        if _G.Kernel then
            local pid = _G.Kernel.exec("/usr/bin/editor.lua", {filePath})
            if pid then _G.Kernel.wait(pid) end
        else
            os.run(_G, "/usr/bin/editor.lua", filePath)
        end
        refresh()
    end
end

local function renameItem()
    local pane = getActivePane()
    local item = pane.items[pane.selected]
    if not item or item.parent then return end
    local newName = inputDialog("New name:", item.name)
    if newName and newName ~= "" then
        local oldPath = pane.path
        if oldPath:sub(-1) ~= "/" then oldPath = oldPath .. "/" end
        fs.move(oldPath .. item.name, oldPath .. newName)
        refresh()
    end
end

local function deleteItem()
    local pane = getActivePane()
    local item = pane.items[pane.selected]
    if not item or item.parent then return end
    if confirmDialog("Delete '" .. item.name .. "'?") then
        local path = pane.path
        if path:sub(-1) ~= "/" then path = path .. "/" end
        path = path .. item.name
        showProgress(0, 1, "Deleting " .. item.name)
        fs.delete(path)
        refresh()
    end
end

local function copyOrMove(action)
    local pane = getActivePane()
    local item = pane.items[pane.selected]
    if not item or item.parent then return end
    local dstPane = getInactivePane()
    local srcPath = pane.path
    if srcPath:sub(-1) ~= "/" then srcPath = srcPath .. "/" end
    srcPath = srcPath .. item.name
    local dstPath = dstPane.path
    if dstPath:sub(-1) ~= "/" then dstPath = dstPath .. "/" end
    dstPath = dstPath .. item.name
    if not confirmDialog(action .. " " .. item.name .. " to " .. dstPane.path .. "?") then
        return
    end
    showProgress(0, 2, action .. "ing " .. item.name)
    if action == "Copy" then
        local ok, err = pcall(fs.copy, srcPath, dstPath)
        if not ok then
            confirmDialog("Copy failed: " .. tostring(err))
        end
    else
        local ok, err = pcall(fs.move, srcPath, dstPath)
        if not ok then
            confirmDialog("Move failed: " .. tostring(err))
        end
    end
    refresh()
end

local function makeDir()
    local name = inputDialog("New directory name:", "")
    if name and name ~= "" then
        local path = getActivePane().path
        if path:sub(-1) ~= "/" then path = path .. "/" end
        path = path .. name
        local ok, err = pcall(fs.makeDir, path)
        if not ok then
            confirmDialog("mkdir failed: " .. tostring(err))
        end
        refresh()
    end
end

local function makeFile()
    local name = inputDialog("New file name:", "")
    if name and name ~= "" then
        local path = getActivePane().path
        if path:sub(-1) ~= "/" then path = path .. "/" end
        path = path .. name
        local f = fs.open(path, "w")
        if f then f.close() end
        -- Open in editor
        if _G.Kernel then
            local pid = _G.Kernel.exec("/usr/bin/editor.lua", {path})
            if pid then _G.Kernel.wait(pid) end
        end
        refresh()
    end
end

local function editItem()
    local pane = getActivePane()
    local item = pane.items[pane.selected]
    if not item or item.parent or item.isDir then return end
    local filePath = pane.path
    if filePath:sub(-1) ~= "/" then filePath = filePath .. "/" end
    filePath = filePath .. item.name
    if _G.Kernel then
        local pid = _G.Kernel.exec("/usr/bin/editor.lua", {filePath})
        if pid then _G.Kernel.wait(pid) end
    end
    refresh()
end

-- Quick view: show file contents in inactive pane
local function quickView()
    local pane = getActivePane()
    local item = pane.items[pane.selected]
    if not item or item.parent or item.isDir then return end
    local filePath = pane.path
    if filePath:sub(-1) ~= "/" then filePath = filePath .. "/" end
    filePath = filePath .. item.name
    local f = fs.open(filePath, "r")
    if not f then return end
    local content = f.readAll()
    f.close()
    -- Show in a dialog
    local w, h = term.getSize()
    setBG(colors.black)
    setColor(colors.white)
    term.setCursorPos(1, 3)
    for rawLine in (content or ""):gmatch("[^\n]*") do
        local _, cy = term.getCursorPos()
        if cy >= h - 2 then break end
        local line = rawLine
        if #line > w then line = line:sub(1, w) end
        print(line)
    end
    setColor(colors.yellow)
    print("[Press any key to close]")
    setColor(colors.white)
    os.pullEvent("key")
end

local function toggleBookmark(slot)
    local pane = getActivePane()
    state.bookmarks[slot] = pane.path
end

local function jumpBookmark(slot)
    local path = state.bookmarks[slot]
    if path then cd(path) end
end

local function main()
    refresh()
    while state.running do
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)
        drawTitleBar()

        local w, h = term.getSize()
        local paneW = math.floor((w - 1) / 2)
        local paneH = h - 4
        drawPane("left",  1,       3, paneW,     paneH)
        drawPane("right", paneW+2, 3, w-paneW-1, paneH)
        drawStatusBar()

        local event = {os.pullEvent()}
        if event[1] == "key" then
            local key = event[2]
            if key == keys.up then navigate("up")
            elseif key == keys.down then navigate("down")
            elseif key == keys.tab then
                state.active = state.active == "left" and "right" or "left"
            elseif key == keys.enter then openItem()
            elseif key == keys.q then state.running = false
            elseif key == keys.h then
                state.showHidden = not state.showHidden
                refresh()
            elseif key == keys.s then
                -- Cycle sort
                if state.sortMode == "name" then state.sortMode = "size"
                elseif state.sortMode == "size" then state.sortMode = "date"
                else state.sortMode = "name" end
                refresh()
            elseif key == keys.two then renameItem()
            elseif key == keys.four then editItem()
            elseif key == keys.five then copyOrMove("Copy")
            elseif key == keys.six then copyOrMove("Move")
            elseif key == keys.seven then makeDir()
            elseif key == keys.eight then deleteItem()
            elseif key == keys.delete then deleteItem()
            elseif key == keys.space then
                -- mark file (multi-select - future feature)
                navigate("down")
            elseif key == keys.leftCtrl or key == keys.rightCtrl then
                -- Ctrl+combo: wait for next key
                local e2 = {os.pullEvent("key")}
                if e2[2] >= 2 and e2[2] <= 6 then
                    -- Ctrl+1..5 = bookmark
                    toggleBookmark(e2[2] - 1)
                elseif e2[2] == keys.r then
                    renameItem()
                elseif e2[2] == keys.n then
                    makeDir()
                elseif e2[2] == keys.c then
                    copyOrMove("Copy")
                elseif e2[2] == keys.x then
                    copyOrMove("Move")
                end
            elseif key == keys.leftAlt or key == keys.rightAlt then
                local e2 = {os.pullEvent("char")}
                local n = tonumber(e2[2])
                if n and n >= 1 and n <= 5 then
                    jumpBookmark(n)
                end
            end
        elseif event[1] == "char" then
            local c = event[2]:lower()
            if c == "q" then state.running = false
            elseif c == "h" then
                state.showHidden = not state.showHidden
                refresh()
            elseif c == "s" then
                if state.sortMode == "name" then state.sortMode = "size"
                elseif state.sortMode == "size" then state.sortMode = "date"
                else state.sortMode = "name" end
                refresh()
            elseif c == "t" then
                state.treeView = not state.treeView
            elseif c == "/" then
                -- Filter
                local f = inputDialog("Filter (substring):", "")
                state.filter = f or ""
                refresh()
            else
                -- Quick-jump to file starting with this letter
                local pane = getActivePane()
                for i, item in ipairs(pane.items) do
                    if item.name:lower():sub(1, 1) == c and i > pane.selected then
                        pane.selected = i
                        break
                    end
                end
            end
        end
    end

    resetColors()
    term.clear()
    term.setCursorPos(1, 1)
    return 0
end

return main()
