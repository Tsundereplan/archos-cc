-- usr/bin/gbrowse.lua  —  Graphical file browser (Finder/Explorer-style)
-- Uses paintutils to draw a 3-column grid of file icons with text labels.
-- Hotkeys: Arrow=move  Enter=open  Backspace=up  q=quit

local FS     = _G.FS or fs
local Kernel = _G.Kernel
local paintutils = paintutils

local args = arg or {...}
local startPath = (args[1] and FS.normalize(args[1]))
    or (Kernel and Kernel.getCwd and Kernel.getCwd())
    or "/"

if not term.isColor or not term.isColor() then
    io.stderr:write("gbrowse: requires a color display\n")
    return 1
end

local state = {
    cwd      = startPath,
    selected = 1,
    scroll    = 1,
    items     = {},
}

-- Reload the directory listing
local function loadEntries()
    state.items = {}
    local list = FS.list(state.cwd) or {}
    local filtered = {}
    for _, n in ipairs(list) do
        if n:sub(1, 1) ~= "." then
            table.insert(filtered, n)
        end
    end
    table.sort(filtered)
    table.insert(state.items, 1, "..")
    for _, n in ipairs(filtered) do
        table.insert(state.items, n)
    end
    if state.selected > #state.items then state.selected = #state.items end
    if state.selected < 1 then state.selected = 1 end
end

local function entryPath(name)
    if name == ".." then
        return FS.getDir(state.cwd)
    end
    return state.cwd .. (state.cwd:sub(-1) == "/" and "" or "/") .. name
end

local function isDirEntry(name)
    if name == ".." then return true end
    return FS.isDir(entryPath(name))
end

-- Classify a file into an icon type
local function iconType(name)
    if name == ".." then return "folder" end
    if isDirEntry(name) then return "folder" end
    local lower = name:lower()
    if lower:sub(-4) == ".lua" then return "lua"
    elseif lower:sub(-4) == ".txt" or lower:sub(-4) == ".log"
        or lower:sub(-3) == ".md" or lower:sub(-5) == ".note" then return "text"
    elseif lower:sub(-4) == ".nfp" or lower:sub(-4) == ".blp" then return "image"
    else return "other" end
end

local function iconColor(t)
    if t == "folder" then return colors.yellow
    elseif t == "lua"   then return colors.green
    elseif t == "text"  then return colors.white
    elseif t == "image" then return colors.blue
    else return colors.gray end
end

local function iconLabel(t)
    if t == "folder" then return "DIR"
    elseif t == "lua"   then return "LUA"
    elseif t == "text"  then return "TXT"
    elseif t == "image" then return "IMG"
    else return "BIN" end
end

-- Build a breadcrumb trail of the current path
local function breadcrumb(path)
    local parts = {}
    for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
    end
    if #parts == 0 then return "/" end
    -- Show the last 3 segments for a compact breadcrumb
    local start = math.max(1, #parts - 2)
    local out = {}
    if start > 1 then table.insert(out, "...") end
    for i = start, #parts do
        table.insert(out, parts[i])
    end
    return "/" .. table.concat(out, " / ")
end

-- Launch the editor on a file path
local function launchEditor(filePath)
    if Kernel and Kernel.exec then
        local pid = Kernel.exec("/usr/bin/editor.lua", { filePath })
        if pid and Kernel.wait then Kernel.wait(pid) end
    else
        pcall(function()
            if shell and shell.run then shell.run("/usr/bin/editor.lua", filePath) end
        end)
    end
end

-- Render the entire GUI
local function render()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()

    -- Title bar with breadcrumb
    term.setCursorPos(1, 1)
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.blue)
    local title = " ArchOS gBrowser  " .. breadcrumb(state.cwd) .. " "
    title = title .. string.rep(" ", math.max(0, w - #title))
    term.write(title:sub(1, w))
    term.setBackgroundColor(colors.black)

    -- Grid layout: 3 columns
    local cols   = 3
    local iconW  = math.floor(w / cols)
    local iconH  = 5  -- 3 tall colored block + 1 spacer + label
    local topY   = 3
    local rowsPerPage = math.floor((h - topY - 1) / iconH)
    local perPage = cols * rowsPerPage

    -- Adjust scroll so selection is visible
    if state.selected < state.scroll then state.scroll = state.selected end
    if state.selected >= state.scroll + perPage then
        state.scroll = state.selected - perPage + 1
    end
    -- Round scroll down to a multiple of perPage so icons stay aligned
    state.scroll = math.floor((state.scroll - 1) / perPage) * perPage + 1

    for i = 0, perPage - 1 do
        local idx = state.scroll + i
        if idx > #state.items then break end
        local name = state.items[idx]
        local col = i % cols
        local row = math.floor(i / cols)
        local bx  = col * iconW + 2
        local by  = topY + row * iconH

        local t   = iconType(name)
        local c   = iconColor(t)
        local lbl = iconLabel(t)
        local isSel = (idx == state.selected)

        -- Selected: draw a white border first (slightly larger box)
        if isSel then
            paintutils.drawBox(bx - 1, by - 1, bx + iconW - 4, by + 3, colors.white)
        end

        -- Icon block (3 tall, full icon width)
        paintutils.drawFilledBox(bx, by, bx + iconW - 5, by + 2, c)
        -- Outline
        paintutils.drawBox(bx, by, bx + iconW - 5, by + 2, colors.lightGray)

        -- Icon label centered inside the block
        term.setCursorPos(bx + math.floor((iconW - 5 - #lbl) / 2), by + 1)
        term.setTextColor(colors.black)
        term.setBackgroundColor(c)
        term.write(lbl)

        -- Type-specific decoration inside the block
        if t == "folder" then
            -- Small triangle in upper-right
            paintutils.drawPixel(bx + iconW - 6, by, colors.brown)
            paintutils.drawPixel(bx + iconW - 7, by, colors.brown)
        elseif t == "image" then
            -- Three little colored pixels in the middle
            paintutils.drawPixel(bx + 2, by + 1, colors.red)
            paintutils.drawPixel(bx + 3, by + 1, colors.lime)
            paintutils.drawPixel(bx + 4, by + 1, colors.cyan)
        end

        -- Filename below the icon
        term.setBackgroundColor(colors.black)
        term.setTextColor(isSel and colors.yellow or colors.white)
        term.setCursorPos(bx, by + 4)
        local shortName = name:sub(1, iconW - 5)
        term.write(shortName)
    end

    -- Footer / status
    term.setCursorPos(1, h)
    term.setTextColor(colors.black)
    term.setBackgroundColor(colors.lightGray)
    local footer = " Arrow=move  Enter=open  Backspace=up  q=quit "
    if state.selected >= 1 and state.items[state.selected] then
        footer = " [" .. state.selected .. "/" .. #state.items .. "] "
            .. state.items[state.selected] .. "  "
            .. footer
    end
    footer = footer .. string.rep(" ", math.max(0, w - #footer))
    term.write(footer:sub(1, w))
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

local function openSelected()
    local name = state.items[state.selected]
    if not name then return end
    local path = entryPath(name)
    if isDirEntry(name) then
        state.cwd = FS.normalize(path)
        state.selected = 1
        state.scroll = 1
        if Kernel and Kernel.setCwd then Kernel.setCwd(state.cwd) end
    else
        launchEditor(path)
    end
end

local function goUp()
    local parent = FS.getDir(state.cwd)
    if parent == state.cwd then return end
    state.cwd = parent
    state.selected = 1
    state.scroll = 1
    if Kernel and Kernel.setCwd then Kernel.setCwd(state.cwd) end
end

-- Main loop ----------------------------------------------------------------

local function main()
    if not FS.exists(state.cwd) then
        io.stderr:write("gbrowse: path not found: " .. state.cwd .. "\n")
        return 1
    end
    if not FS.isDir(state.cwd) then
        io.stderr:write("gbrowse: not a directory: " .. state.cwd .. "\n")
        return 1
    end

    loadEntries()
    term.setCursorBlink(false)

    local cols = 3
    while true do
        render()
        local event = { os.pullEvent() }
        local ev = event[1]

        if ev == "key" then
            local key = event[2]
            if key == (keys and keys.q or 16) then
                break
            elseif key == (keys and keys.up or 17) then
                state.selected = math.max(1, state.selected - cols)
            elseif key == (keys and keys.down or 19) then
                state.selected = math.min(#state.items, state.selected + cols)
            elseif key == (keys and keys.left or 203) then
                state.selected = math.max(1, state.selected - 1)
            elseif key == (keys and keys.right or 205) then
                state.selected = math.min(#state.items, state.selected + 1)
            elseif key == (keys and keys.enter or 28) then
                openSelected()
            elseif key == (keys and keys.backspace or 14) then
                goUp()
            end
        elseif ev == "mouse_click" then
            -- mouse_click: button, x, y
            local _, mx, my = event[2], event[3], event[4]
            local w, h = term.getSize()
            local iconW = math.floor(w / cols)
            local topY = 3
            local iconH = 5
            local rowsPerPage = math.floor((h - topY - 1) / iconH)
            local perPage = cols * rowsPerPage
            if my >= topY then
                local col = math.floor((mx - 1) / iconW)
                local row = math.floor((my - topY) / iconH)
                if col >= 0 and col < cols and row >= 0 and row < rowsPerPage then
                    local idx = state.scroll + row * cols + col
                    if idx >= 1 and idx <= #state.items then
                        state.selected = idx
                        openSelected()
                    end
                end
            end
        end
    end

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    return 0
end

return main()
