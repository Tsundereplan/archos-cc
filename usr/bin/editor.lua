--[[
    usr/bin/editor.lua  —  Text editor with Lua syntax highlighting
    ===============================================================
    Usage: editor [FILE]
    Without a FILE, opens an empty buffer.

    Key bindings:
      Ctrl+S         save
      Ctrl+Q         quit (without save)
      Ctrl+X         quit (ask to save if modified)
      Ctrl+F         find
      Ctrl+G         goto line
      Ctrl+D         delete line
      Ctrl+Z         undo (last 50 changes)
      Arrow keys     move cursor
      Page Up/Down   scroll
      Home/End       move to start/end of line
      Tab            insert 2 spaces (no tab chars in CC:Tweaked)
      Backspace      delete char before cursor
      Enter          new line
]]

local Editor = {}

-- Color palette for syntax highlighting
local HL = {
    default  = colors.white,
    keyword  = colors.lightBlue,
    string   = colors.green,
    comment  = colors.gray,
    number   = colors.orange,
    func     = colors.yellow,
    ident    = colors.lightGray,
    bg       = colors.black,
}

-- Lua keywords
local KEYWORDS = {
    ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
    ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
    ["function"] = true, ["if"] = true, ["in"] = true, ["local"] = true,
    ["nil"] = true, ["not"] = true, ["or"] = true, ["repeat"] = true,
    ["return"] = true, ["then"] = true, ["true"] = true, ["until"] = true,
    ["while"] = true, ["goto"] = true,
}

-- Editor state
local state = {
    filename = nil,
    lines = { "" },
    cursorX = 1,  -- 1-indexed
    cursorY = 1,
    scrollX = 0,
    scrollY = 0,
    modified = false,
    undoStack = {},
    message = "",
    messageTime = 0,
    findQuery = "",
    mode = "edit",  -- "edit", "find", "command"
    commandBuffer = "",
}

-- Save current state to undo stack
local function pushUndo()
    local snapshot = {
        lines = {},
        cursorX = state.cursorX,
        cursorY = state.cursorY,
    }
    for i, line in ipairs(state.lines) do
        snapshot.lines[i] = line
    end
    table.insert(state.undoStack, snapshot)
    if #state.undoStack > 50 then table.remove(state.undoStack, 1) end
end

local function showMessage(msg)
    state.message = msg
    state.messageTime = os.clock()
end

-- Compute syntax highlighting for a single line.
-- Returns a list of {text, color} chunks.
local function highlightLine(line)
    local chunks = {}
    local i = 1
    local n = #line
    while i <= n do
        local c = line:sub(i, i)
        -- Comments: -- to end of line
        if c == "-" and line:sub(i+1, i+1) == "-" then
            table.insert(chunks, { text = line:sub(i), color = HL.comment })
            break
        end
        -- Strings: "..." or '...'
        if c == '"' or c == "'" then
            local quote = c
            local endPos = i + 1
            while endPos <= n and line:sub(endPos, endPos) ~= quote do
                if line:sub(endPos, endPos) == "\\" then endPos = endPos + 1 end
                endPos = endPos + 1
            end
            table.insert(chunks, { text = line:sub(i, endPos), color = HL.string })
            i = endPos + 1
        -- Strings: [[...]]
        elseif c == "[" and line:sub(i+1, i+1) == "[" then
            local endPos = line:find("]]", i+2, true)
            endPos = endPos or n
            table.insert(chunks, { text = line:sub(i, endPos+1), color = HL.string })
            i = endPos + 2
        -- Numbers
        elseif c:match("[0-9]") then
            local endPos = i
            while endPos <= n and line:sub(endPos, endPos):match("[0-9%.xXa-fA-F]") do
                endPos = endPos + 1
            end
            table.insert(chunks, { text = line:sub(i, endPos-1), color = HL.number })
            i = endPos
        -- Identifiers (keywords or function names)
        elseif c:match("[%w_]") then
            local endPos = i
            while endPos <= n and line:sub(endPos, endPos):match("[%w_]") do
                endPos = endPos + 1
            end
            local word = line:sub(i, endPos-1)
            if KEYWORDS[word] then
                table.insert(chunks, { text = word, color = HL.keyword })
            elseif line:sub(endPos, endPos) == "(" then
                table.insert(chunks, { text = word, color = HL.func })
            else
                table.insert(chunks, { text = word, color = HL.ident })
            end
            i = endPos
        else
            -- Single non-ident char
            table.insert(chunks, { text = c, color = HL.default })
            i = i + 1
        end
    end
    return chunks
end

-- Render the editor screen
local function render()
    local w, h = term.getSize()
    term.setBackgroundColor(HL.bg)
    term.clear()

    -- Title bar
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.blue)
    term.setCursorPos(1, 1)
    local title = " editor "
    if state.filename then
        title = title .. "- " .. state.filename .. " "
    else
        title = title .. "- [untitled] "
    end
    if state.modified then
        title = title .. "* "
    end
    -- Pad title to width
    title = title .. string.rep(" ", math.max(0, w - #title))
    term.write(title:sub(1, w))
    term.setBackgroundColor(HL.bg)

    -- Body: render lines
    local bodyStart = 2
    local bodyEnd = h - 2  -- leave 2 lines for status & command
    for screenY = bodyStart, bodyEnd do
        local lineIdx = screenY - bodyStart + 1 + state.scrollY
        term.setCursorPos(1, screenY)
        if lineIdx <= #state.lines then
            local line = state.lines[lineIdx]
            -- Line number column
            term.setTextColor(colors.gray)
            term.write(string.format("%3d ", lineIdx))
            -- Render line with highlighting, applying horizontal scroll
            local visibleLine = line:sub(state.scrollX + 1)
            local chunks = highlightLine(visibleLine)
            for _, chunk in ipairs(chunks) do
                term.setTextColor(chunk.color)
                term.write(chunk.text)
            end
        else
            term.setTextColor(colors.gray)
            term.write(string.format("%3d ", lineIdx))
            term.setTextColor(colors.gray)
            term.write("~")
        end
    end

    -- Status bar
    term.setBackgroundColor(colors.lightGray)
    term.setTextColor(colors.black)
    term.setCursorPos(1, h - 1)
    local status = string.format(" Ln %d, Col %d  Lines: %d  %s",
        state.cursorY, state.cursorX, #state.lines, state.modified and "[modified]" or "[clean]")
    status = status .. string.rep(" ", math.max(0, w - #status))
    term.write(status:sub(1, w))
    term.setBackgroundColor(HL.bg)

    -- Command/message bar
    term.setTextColor(colors.yellow)
    term.setCursorPos(1, h)
    local cmdline = ""
    if state.mode == "find" then
        cmdline = "Find: " .. state.findQuery .. "_"
    elseif state.mode == "command" then
        cmdline = ":" .. state.commandBuffer .. "_"
    elseif state.message ~= "" and (os.clock() - state.messageTime) < 3 then
        cmdline = state.message
    else
        cmdline = "Ctrl+S=Save  Ctrl+Q=Quit  Ctrl+F=Find  Ctrl+G=Goto"
    end
    cmdline = cmdline .. string.rep(" ", math.max(0, w - #cmdline))
    term.write(cmdline:sub(1, w))

    -- Position cursor
    local curLine = state.lines[state.cursorY] or ""
    local curScreenY = state.cursorY - state.scrollY + bodyStart
    local curScreenX = 4 + (state.cursorX - 1) - state.scrollX  -- +4 for "  N " line number
    if curScreenY >= bodyStart and curScreenY <= bodyEnd then
        term.setCursorPos(math.max(1, curScreenX), curScreenY)
    end
end

-- Adjust scroll so cursor is visible
local function adjustScroll()
    local w, h = term.getSize()
    local bodyStart = 2
    local bodyEnd = h - 2
    local bodyHeight = bodyEnd - bodyStart + 1
    -- Vertical scroll
    if state.cursorY < state.scrollY + 1 then
        state.scrollY = state.cursorY - 1
    elseif state.cursorY > state.scrollY + bodyHeight then
        state.scrollY = state.cursorY - bodyHeight
    end
    -- Horizontal scroll
    local visibleWidth = w - 4
    if state.cursorX < state.scrollX + 1 then
        state.scrollX = state.cursorX - 1
    elseif state.cursorX > state.scrollX + visibleWidth then
        state.scrollX = state.cursorX - visibleWidth
    end
end

-- Insert a character at cursor position
local function insertChar(c)
    pushUndo()
    local line = state.lines[state.cursorY] or ""
    state.lines[state.cursorY] = line:sub(1, state.cursorX - 1) .. c .. line:sub(state.cursorX)
    state.cursorX = state.cursorX + 1
    state.modified = true
end

-- Insert a newline at cursor position
local function insertNewline()
    pushUndo()
    local line = state.lines[state.cursorY] or ""
    local before = line:sub(1, state.cursorX - 1)
    local after = line:sub(state.cursorX)
    table.insert(state.lines, state.cursorY + 1, after)
    state.lines[state.cursorY] = before
    state.cursorY = state.cursorY + 1
    state.cursorX = 1
    state.modified = true
end

-- Delete the char before cursor
local function backspace()
    pushUndo()
    if state.cursorX > 1 then
        local line = state.lines[state.cursorY]
        state.lines[state.cursorY] = line:sub(1, state.cursorX - 2) .. line:sub(state.cursorX)
        state.cursorX = state.cursorX - 1
        state.modified = true
    elseif state.cursorY > 1 then
        -- Merge with previous line
        local prevLine = state.lines[state.cursorY - 1]
        local curLine = state.lines[state.cursorY]
        state.cursorX = #prevLine + 1
        state.lines[state.cursorY - 1] = prevLine .. curLine
        table.remove(state.lines, state.cursorY)
        state.cursorY = state.cursorY - 1
        state.modified = true
    end
end

-- Delete current line
local function deleteLine()
    pushUndo()
    if #state.lines > 1 then
        table.remove(state.lines, state.cursorY)
        if state.cursorY > #state.lines then
            state.cursorY = #state.lines
        end
    else
        state.lines[1] = ""
    end
    state.cursorX = 1
    state.modified = true
end

-- Move cursor
local function moveCursor(dx, dy)
    state.cursorY = math.max(1, math.min(#state.lines, state.cursorY + dy))
    local line = state.lines[state.cursorY] or ""
    state.cursorX = math.max(1, math.min(#line + 1, state.cursorX + dx))
end

local function moveCursorStart()
    state.cursorX = 1
end

local function moveCursorEnd()
    local line = state.lines[state.cursorY] or ""
    state.cursorX = #line + 1
end

local function pageUp()
    local _, h = term.getSize()
    moveCursor(0, -(h - 4))
end

local function pageDown()
    local _, h = term.getSize()
    moveCursor(0, h - 4)
end

-- Save file
local function saveFile()
    if not state.filename then
        -- Prompt for filename
        term.setCursorPos(1, select(2, term.getSize()))
        term.write("Save as: ")
        state.filename = read()
        if not state.filename then return false end
    end
    local f = fs.open(state.filename, "w")
    if not f then
        showMessage("Error: cannot write to " .. state.filename)
        return false
    end
    for i, line in ipairs(state.lines) do
        f.write(line)
        if i < #state.lines then f.write("\n") end
    end
    f.close()
    state.modified = false
    showMessage("Saved: " .. state.filename)
    return true
end

-- Load file
local function loadFile(path)
    state.filename = path
    local f = fs.open(path, "r")
    if not f then
        showMessage("Cannot open: " .. path)
        return false
    end
    local content = f.readAll()
    f.close()
    state.lines = {}
    for line in content:gmatch("[^\n]*") do
        table.insert(state.lines, line)
    end
    if #state.lines == 0 then state.lines = { "" } end
    state.cursorX = 1
    state.cursorY = 1
    state.scrollX = 0
    state.scrollY = 0
    state.modified = false
    return true
end

-- Find next occurrence of query from current position
local function findNext(query)
    if not query or query == "" then return end
    local startLine = state.cursorY
    local startCol = state.cursorX + 1
    for i = startLine, #state.lines do
        local line = state.lines[i]
        local from = (i == startLine) and startCol or 1
        local pos = line:find(query, from, true)
        if pos then
            state.cursorY = i
            state.cursorX = pos
            adjustScroll()
            return true
        end
    end
    -- Wrap around
    for i = 1, startLine do
        local line = state.lines[i]
        local pos = line:find(query, 1, true)
        if pos then
            state.cursorY = i
            state.cursorX = pos
            adjustScroll()
            showMessage("Wrapped around")
            return true
        end
    end
    showMessage("Not found: " .. query)
    return false
end

-- Goto line
local function gotoLine(n)
    if n < 1 or n > #state.lines then
        showMessage("Line out of range")
        return
    end
    state.cursorY = n
    state.cursorX = 1
    adjustScroll()
end

-- Undo
local function undo()
    if #state.undoStack == 0 then
        showMessage("Nothing to undo")
        return
    end
    local snapshot = table.remove(state.undoStack)
    state.lines = snapshot.lines
    state.cursorX = snapshot.cursorX
    state.cursorY = snapshot.cursorY
    state.modified = true
end

-- Main loop
local function main()
    -- Parse args (via arg table or _G.arg)
    local args = arg or {}
    if #args > 0 then
        loadFile(args[1])
    end

    while true do
        render()
        local event = { os.pullEvent() }
        local ev = event[1]

        if ev == "key" then
            local key = event[2]
            if state.mode == "find" then
                if key == keys.enter then
                    findNext(state.findQuery)
                    state.mode = "edit"
                elseif key == keys.backspace then
                    state.findQuery = state.findQuery:sub(1, -2)
                elseif key == keys.leftCtrl or key == keys.rightCtrl then
                    -- Ctrl+something, ignore in find mode
                end
            elseif state.mode == "command" then
                if key == keys.enter then
                    local cmd = state.commandBuffer
                    state.commandBuffer = ""
                    state.mode = "edit"
                    if cmd:sub(1, 1) == "q" then
                        if state.modified and not cmd:match("q!") then
                            showMessage("File modified. Use :q! to force quit.")
                        else
                            return 0
                        end
                    elseif cmd:sub(1, 1) == "w" then
                        saveFile()
                        if cmd:match("wq") then return 0 end
                    elseif cmd:sub(1, 1) == "g" then
                        local n = tonumber(cmd:match("g%s*(%d+)"))
                        if n then gotoLine(n) end
                    end
                elseif key == keys.backspace then
                    state.commandBuffer = state.commandBuffer:sub(1, -2)
                end
            else
                -- Edit mode
                if key == keys.leftCtrl or key == keys.rightCtrl then
                    -- Wait for next key
                    local e2 = { os.pullEvent("key") }
                    local k2 = e2[2]
                    if k2 == keys.s then
                        saveFile()
                    elseif k2 == keys.q then
                        return 0
                    elseif k2 == keys.x then
                        if state.modified then
                            term.setCursorPos(1, select(2, term.getSize()))
                            term.write("Save before quit? [Y/n] ")
                            local c = read()
                            if c == "" or c:lower() == "y" then
                                saveFile()
                            end
                        end
                        return 0
                    elseif k2 == keys.f then
                        state.mode = "find"
                        state.findQuery = ""
                    elseif k2 == keys.g then
                        state.mode = "command"
                        state.commandBuffer = ""
                    elseif k2 == keys.d then
                        deleteLine()
                    elseif k2 == keys.z then
                        undo()
                    end
                elseif key == keys.up then
                    moveCursor(0, -1)
                elseif key == keys.down then
                    moveCursor(0, 1)
                elseif key == keys.left then
                    moveCursor(-1, 0)
                elseif key == keys.right then
                    moveCursor(1, 0)
                elseif key == keys.home then
                    moveCursorStart()
                elseif key == keys["end"] then
                    moveCursorEnd()
                elseif key == keys.pageUp then
                    pageUp()
                elseif key == keys.pageDown then
                    pageDown()
                elseif key == keys.backspace then
                    backspace()
                elseif key == keys.enter then
                    insertNewline()
                elseif key == keys.tab then
                    insertChar("  ")
                end
            end
            adjustScroll()
        elseif ev == "char" then
            local c = event[2]
            if state.mode == "find" then
                state.findQuery = state.findQuery .. c
            elseif state.mode == "command" then
                state.commandBuffer = state.commandBuffer .. c
            else
                insertChar(c)
            end
        elseif ev == "paste" then
            local text = event[2]
            for c in text:gmatch(".") do
                if c == "\n" then
                    insertNewline()
                else
                    insertChar(c)
                end
            end
        elseif ev == "mouse_click" then
            -- Click to move cursor
            local _, mx, my = event[2], event[3], event[4]
            -- Account for line number column (4 chars) + body start (y=2)
            local newCol = mx - 4 + 1 + state.scrollX
            local newY = my - 2 + 1 + state.scrollY
            if newY >= 1 and newY <= #state.lines then
                state.cursorY = newY
                local line = state.lines[state.cursorY] or ""
                state.cursorX = math.max(1, math.min(#line + 1, newCol))
                adjustScroll()
            end
        elseif ev == "mouse_scroll" then
            -- Scroll up/down
            local dir = event[2]
            if dir == -1 then
                -- Scroll up
                state.cursorY = math.max(1, state.cursorY - 3)
            else
                -- Scroll down
                state.cursorY = math.min(#state.lines, state.cursorY + 3)
            end
            adjustScroll()
        end
    end
end

return main()
