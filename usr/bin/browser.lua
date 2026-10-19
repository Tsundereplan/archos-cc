-- usr/bin/browser.lua  —  Text-mode file browser (midnight commander-style)
-- Two-pane TUI: left = directory listing, right = file/directory preview.
-- Hotkeys: Tab=switch pane  Enter=open  F2=rename  F5=copy  F6=move  F8=delete
--          h=toggle hidden  Backspace/..=up  q=quit

local FS   = _G.FS or fs
local Kernel = _G.Kernel

local args = arg or {...}
local startPath = (args[1] and FS.normalize(args[1]))
    or (Kernel and Kernel.getCwd and Kernel.getCwd())
    or "/"

-- Browser state
local state = {
    cwd        = startPath,
    selected   = 1,
    scroll     = 1,
    showHidden = false,
    activePane = "left",   -- "left" or "right"
    items      = {},
    message    = "",
}

-- Truncate a path to fit a width, prefixing with "..."
local function truncatePath(path, maxLen)
    if #path <= maxLen then return path end
    return "..." .. path:sub(#path - maxLen + 4)
end

-- Compute the full path of a list entry
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

-- Load (or reload) the listing of the current directory
local function loadEntries()
    state.items = {}
    local list = FS.list(state.cwd) or {}
    local filtered = {}
    for _, n in ipairs(list) do
        if state.showHidden or n:sub(1, 1) ~= "." then
            table.insert(filtered, n)
        end
    end
    table.sort(filtered)
    -- Always show ".." first so the user can navigate up
    table.insert(state.items, 1, "..")
    for _, n in ipairs(filtered) do
        table.insert(state.items, n)
    end
    if state.selected > #state.items then state.selected = #state.items end
    if state.selected < 1 then state.selected = 1 end
end

-- Launch the editor on a file path.  Returns when the editor exits.
local function launchEditor(filePath)
    if Kernel and Kernel.exec then
        local pid = Kernel.exec("/usr/bin/editor.lua", { filePath })
        if pid and Kernel.wait then Kernel.wait(pid) end
    else
        -- Fallback path for environments without the kernel
        local ok = pcall(function()
            if shell and shell.run then shell.run("/usr/bin/editor.lua", filePath)
            elseif fs.exists("/usr/bin/editor.lua") then dofile("/usr/bin/editor.lua") end
        end)
        if not ok then
            io.stderr:write("browser: cannot launch editor\n")
        end
    end
end

-- Prompt the user with a label, return what they typed (or nil on empty/escape)
local function prompt(label)
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
    term.setCursorPos(1, h)
    term.clearLine()
    term.write(label)
    local result = read()
    term.setCursorPos(1, h)
    term.clearLine()
    return result
end

-- Action handlers ----------------------------------------------------------

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

local function renameSelected()
    local name = state.items[state.selected]
    if not name or name == ".." then
        state.message = "cannot rename '..'"
        return
    end
    local newName = prompt("Rename '" .. name .. "' to: ")
    if not newName or newName == "" or newName == name then return end
    local oldPath = entryPath(name)
    local newPath = state.cwd .. (state.cwd:sub(-1) == "/" and "" or "/") .. newName
    local ok, err
    if FS.move then ok, err = FS.move(oldPath, newPath)
    else fs.move(FS.resolve(oldPath), FS.resolve(newPath)); ok = true end
    if not ok then
        state.message = "rename failed: " .. tostring(err)
    else
        state.message = "renamed -> " .. newName
        loadEntries()
    end
end

local function copySelected()
    local name = state.items[state.selected]
    if not name or name == ".." then return end
    local dest = prompt("Copy '" .. name .. "' to: ")
    if not dest or dest == "" then return end
    dest = FS.normalize(dest)
    local src = entryPath(name)
    local ok, err
    if FS.copy then ok, err = FS.copy(src, dest)
    else fs.copy(FS.resolve(src), FS.resolve(dest)); ok = true end
    if not ok then
        state.message = "copy failed: " .. tostring(err)
    else
        state.message = "copied -> " .. dest
    end
end

local function moveSelected()
    local name = state.items[state.selected]
    if not name or name == ".." then return end
    local dest = prompt("Move '" .. name .. "' to: ")
    if not dest or dest == "" then return end
    dest = FS.normalize(dest)
    local src = entryPath(name)
    local ok, err
    if FS.move then ok, err = FS.move(src, dest)
    else fs.move(FS.resolve(src), FS.resolve(dest)); ok = true end
    if not ok then
        state.message = "move failed: " .. tostring(err)
    else
        state.message = "moved -> " .. dest
        loadEntries()
    end
end

local function deleteSelected()
    local name = state.items[state.selected]
    if not name or name == ".." then return end
    local answer = prompt("Delete '" .. name .. "'? [y/N]: ")
    if not answer or answer:lower() ~= "y" then
        state.message = "aborted"
        return
    end
    local path = entryPath(name)
    local ok, err
    if FS.delete then ok, err = FS.delete(path)
    else fs.delete(FS.resolve(path)); ok = true end
    if not ok then
        state.message = "delete failed: " .. tostring(err)
    else
        state.message = "deleted: " .. name
        loadEntries()
    end
end

-- Rendering ----------------------------------------------------------------

local function render()
    local w, h = term.getSize()
    local leftWidth = math.max(10, math.floor(w / 2) - 1)
    local rightX    = leftWidth + 3
    local rightW    = w - rightX + 1
    local bodyTop   = 3
    local bodyBot   = h - 1
    local bodyH     = bodyBot - bodyTop + 1

    term.setBackgroundColor(colors.black)
    term.clear()

    -- Title bar
    term.setCursorPos(1, 1)
    if term.isColor() then
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.blue)
    end
    local title = " ArchOS Browser  " .. truncatePath(state.cwd, w - 18)
    title = title .. string.rep(" ", math.max(0, w - #title))
    term.write(title:sub(1, w))
    term.setBackgroundColor(colors.black)

    -- Column headers
    term.setCursorPos(1, 2)
    if term.isColor() then
        term.setTextColor(state.activePane == "left" and colors.yellow or colors.gray)
    end
    term.write("Name")
    term.setCursorPos(rightX, 2)
    if term.isColor() then
        term.setTextColor(state.activePane == "right" and colors.yellow or colors.gray)
    end
    term.write("Preview")

    -- Vertical divider
    if term.isColor() then term.setTextColor(colors.gray) end
    for y = bodyTop, bodyBot do
        term.setCursorPos(leftWidth + 2, y)
        term.write("|")
    end

    -- Left pane: scrollable directory listing
    -- Adjust scroll so selection is visible
    if state.selected < state.scroll then state.scroll = state.selected end
    if state.selected >= state.scroll + bodyH then
        state.scroll = state.selected - bodyH + 1
    end
    for i = 1, bodyH do
        local idx = state.scroll + i - 1
        local y = bodyTop + i - 1
        term.setCursorPos(1, y)
        if idx <= #state.items then
            local name = state.items[idx]
            local isSel = (idx == state.selected)
            local isD = isDirEntry(name)
            if isSel and state.activePane == "left" then
                term.setBackgroundColor(colors.white)
                term.setTextColor(colors.black)
            else
                term.setBackgroundColor(colors.black)
                if not term.isColor() then
                    term.setTextColor(colors.white)
                elseif isD then
                    term.setTextColor(colors.lightBlue)
                elseif name:sub(-4) == ".lua" then
                    term.setTextColor(colors.green)
                elseif name:sub(1, 1) == "." then
                    term.setTextColor(colors.gray)
                else
                    term.setTextColor(colors.white)
                end
            end
            local display = name
            if isD and name ~= ".." then display = display .. "/" end
            display = display .. string.rep(" ", leftWidth - #display)
            term.write(display:sub(1, leftWidth))
        else
            term.setBackgroundColor(colors.black)
            term.write(string.rep(" ", leftWidth))
        end
    end
    term.setBackgroundColor(colors.black)
    if term.isColor() then term.setTextColor(colors.white) end

    -- Right pane: preview of the currently selected item
    local selName = state.items[state.selected]
    if selName then
        local selPath = entryPath(selName)
        if isDirEntry(selName) then
            if term.isColor() then term.setTextColor(colors.lightBlue) end
            term.setCursorPos(rightX, bodyTop)
            term.write("Contents of " .. selName .. ":")
            local list = FS.list(selPath) or {}
            table.sort(list)
            for i, n in ipairs(list) do
                if i > bodyH - 1 then break end
                term.setCursorPos(rightX, bodyTop + i)
                local childPath = selPath .. (selPath:sub(-1) == "/" and "" or "/") .. n
                if FS.isDir(childPath) then
                    if term.isColor() then term.setTextColor(colors.lightBlue) end
                    term.write(n .. "/")
                else
                    if term.isColor() then term.setTextColor(colors.white) end
                    term.write(n)
                end
            end
        else
            -- File preview: show name + size + first few lines
            if term.isColor() then term.setTextColor(colors.green) end
            term.setCursorPos(rightX, bodyTop)
            term.write("File: " .. selName)
            local size = FS.getSize and FS.getSize(selPath) or fs.getSize(FS.resolve(selPath))
            if term.isColor() then term.setTextColor(colors.gray) end
            term.setCursorPos(rightX, bodyTop + 1)
            term.write("Size: " .. tostring(size) .. " bytes")
            local f = FS.open(selPath, "r")
            if f then
                if term.isColor() then term.setTextColor(colors.white) end
                local lineNum = 0
                local maxLines = bodyH - 3
                local line = f.readLine and f.readLine() or f.readAll():gmatch("[^\n]*")()
                while line and lineNum < maxLines do
                    term.setCursorPos(rightX, bodyTop + 3 + lineNum)
                    term.write(line:sub(1, rightW))
                    lineNum = lineNum + 1
                    line = f.readLine and f.readLine()
                end
                f.close()
            end
        end
    end

    -- Hotkey bar
    term.setCursorPos(1, h)
    if term.isColor() then
        term.setTextColor(colors.black)
        term.setBackgroundColor(colors.lightGray)
    end
    local hk = " Tab=switch  Enter=open  F2=rename  F5=copy  F6=move  F8=delete  h=hidden  q=quit "
    hk = hk .. string.rep(" ", math.max(0, w - #hk))
    term.write(hk:sub(1, w))

    -- Message overlay (if any) on the line above the hotkey bar
    if state.message ~= "" then
        term.setCursorPos(1, h - 1)
        if term.isColor() then term.setTextColor(colors.yellow) end
        term.setBackgroundColor(colors.black)
        term.write(state.message:sub(1, w))
    end
    term.setBackgroundColor(colors.black)
    if term.isColor() then term.setTextColor(colors.white) end
end

-- Main loop ----------------------------------------------------------------

local function main()
    if not FS.exists(state.cwd) then
        io.stderr:write("browser: path not found: " .. state.cwd .. "\n")
        return 1
    end
    if not FS.isDir(state.cwd) then
        io.stderr:write("browser: not a directory: " .. state.cwd .. "\n")
        return 1
    end

    loadEntries()
    term.setCursorBlink(false)

    while true do
        render()
        local event = { os.pullEvent() }
        local ev = event[1]

        if ev == "key" then
            local key = event[2]
            state.message = ""

            if key == (keys and keys.q or 16) then
                break
            elseif key == (keys and keys.h or 35) then
                state.showHidden = not state.showHidden
                loadEntries()
                state.message = "hidden files " .. (state.showHidden and "shown" or "hidden")
            elseif key == (keys and keys.tab or 15) then
                state.activePane = (state.activePane == "left") and "right" or "left"
            elseif key == (keys and keys.up or 17) then
                state.selected = math.max(1, state.selected - 1)
            elseif key == (keys and keys.down or 19) then
                state.selected = math.min(#state.items, state.selected + 1)
            elseif key == (keys and keys.left or 203) then
                if state.activePane == "right" then
                    state.activePane = "left"
                else
                    goUp()
                end
            elseif key == (keys and keys.right or 205) then
                if state.activePane == "left" then
                    state.activePane = "right"
                else
                    openSelected()
                end
            elseif key == (keys and keys.enter or 28) then
                openSelected()
            elseif key == (keys and keys.backspace or 14) then
                goUp()
            elseif key == (keys and keys.f2  or 60) then
                renameSelected()
            elseif key == (keys and keys.f5  or 63) then
                copySelected()
            elseif key == (keys and keys.f6  or 64) then
                moveSelected()
            elseif key == (keys and keys.f8  or 66) then
                deleteSelected()
            end
        elseif ev == "mouse_scroll" then
            -- mouse_scroll: direction, x, y
            local dir = event[2]
            if dir == 1 then
                state.selected = math.min(#state.items, state.selected + 1)
            else
                state.selected = math.max(1, state.selected - 1)
            end
        end
    end

    -- Restore terminal
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    term.setCursorBlink(true)
    return 0
end

return main()
