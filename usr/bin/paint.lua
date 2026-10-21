-- usr/bin/paint.lua  —  Pixel art editor (extended CC paint)
-- Canvas size adapts to the screen (max 50x20); palette of 16 colors.
-- Tools: brush (1px), eraser, line (click-to-click), fill (bucket)
-- Save format: standard .nfp (one row per line, one hex char per pixel)
--
-- Keys:
--   1-9, 0, a-f   select palette color (1-16)
--   b              brush tool
--   e              eraser tool
--   l              line tool
--   f              fill (bucket) tool
--   s              save
--   o              open
--   q              quit
--   c              clear canvas

local FS         = _G.FS or fs
local Kernel     = _G.Kernel
local paintutils = paintutils

if not term.isColor or not term.isColor() then
    io.stderr:write("paint: requires a color display\n")
    return 1
end

local args = arg or {...}

-- Check for --monitor <side> argument
local monitorRedirect = nil
local useMonitorTouch = false
for i, a in ipairs(args) do
    if a == "--monitor" and args[i+1] then
        local side = args[i+1]
        if peripheral.isPresent(side) and peripheral.getType(side) == "monitor" then
            monitorRedirect = peripheral.wrap(side)
            useMonitorTouch = true
            -- Remove these two args so filename parsing works
            table.remove(args, i)
            table.remove(args, i)
        end
        break
    end
end

-- If using a monitor, redirect term to it
if monitorRedirect then
    monitorRedirect.setBackgroundColor(colors.black)
    monitorRedirect.setTextColor(colors.white)
    monitorRedirect.clear()
    monitorRedirect.setCursorPos(1, 1)
    term.redirect(monitorRedirect)
end

-- Layout dimensions (adaptive to screen, capped at 50x20)
local W, H = term.getSize()
local CANVAS_W = math.min(50, W)
local CANVAS_H = math.min(20, H - 4)  -- leave 4 rows for palette + status

-- CC palette: the order here matches the standard .nfp character order
local PALETTE = {
    colors.white, colors.orange, colors.magenta, colors.lightBlue,
    colors.yellow, colors.lime, colors.pink, colors.gray,
    colors.lightGray, colors.cyan, colors.purple, colors.blue,
    colors.brown, colors.green, colors.red, colors.black,
}

-- Map color value -> .nfp hex char (and back)
local INDEX_TO_CHAR = {
    [colors.white]      = "0",
    [colors.orange]     = "1",
    [colors.magenta]    = "2",
    [colors.lightBlue]  = "3",
    [colors.yellow]     = "4",
    [colors.lime]       = "5",
    [colors.pink]       = "6",
    [colors.gray]       = "7",
    [colors.lightGray]  = "8",
    [colors.cyan]       = "9",
    [colors.purple]     = "a",
    [colors.blue]       = "b",
    [colors.brown]      = "c",
    [colors.green]      = "d",
    [colors.red]        = "e",
    [colors.black]      = "f",
}

local CHAR_TO_INDEX = {}
for k, v in pairs(INDEX_TO_CHAR) do
    CHAR_TO_INDEX[v] = k
end

-- Map keyboard char -> palette slot (1-16)
local KEY_TO_SLOT = {
    ["1"] = 1,  ["2"] = 2,  ["3"] = 3,  ["4"] = 4,  ["5"] = 5,
    ["6"] = 6,  ["7"] = 7,  ["8"] = 8,  ["9"] = 9,  ["0"] = 10,
    ["a"] = 11, ["b"] = 12, ["c"] = 13, ["d"] = 14, ["e"] = 15, ["f"] = 16,
}

local TOOL_NAMES = { brush = "Brush", eraser = "Eraser", line = "Line", fill = "Fill" }

-- State --------------------------------------------------------------------

local state = {
    canvas       = {},     -- [y][x] = colorValue (or nil for transparent)
    currentColor = 1,      -- palette slot 1-16
    tool         = "brush",
    filename     = args[1],
    lineStart    = nil,    -- {x, y} for line tool's first click
    status       = "",
}

-- Initialize an empty canvas
for y = 1, CANVAS_H do
    state.canvas[y] = {}
    for x = 1, CANVAS_W do
        state.canvas[y][x] = nil
    end
end

-- File I/O ----------------------------------------------------------------

local function loadFile(path)
    if not FS.exists(path) then
        state.status = "file not found: " .. path
        return false
    end
    local f = FS.open(path, "r")
    if not f then
        state.status = "cannot open: " .. path
        return false
    end
    -- Clear canvas first
    for y = 1, CANVAS_H do
        for x = 1, CANVAS_W do
            state.canvas[y][x] = nil
        end
    end
    local y = 1
    local line = f.readLine and f.readLine()
    while line and y <= CANVAS_H do
        for x = 1, math.min(#line, CANVAS_W) do
            local ch = line:sub(x, x)
            local color = CHAR_TO_INDEX[ch]
            if color then
                state.canvas[y][x] = color
            end
        end
        y = y + 1
        line = f.readLine and f.readLine()
    end
    f.close()
    state.filename = path
    state.status = "loaded: " .. path
    return true
end

local function saveFile(path)
    local f = FS.open(path, "w")
    if not f then
        state.status = "cannot save: " .. path
        return false
    end
    for y = 1, CANVAS_H do
        local line = {}
        for x = 1, CANVAS_W do
            local c = state.canvas[y][x]
            if c and INDEX_TO_CHAR[c] then
                line[x] = INDEX_TO_CHAR[c]
            else
                line[x] = " "  -- transparent
            end
        end
        f.writeLine(table.concat(line, ""))
    end
    f.close()
    state.filename = path
    state.status = "saved: " .. path
    return true
end

-- Prompt for input on the status line
local function prompt(label)
    term.setCursorPos(1, H)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
    term.clearLine()
    term.write(label)
    local result = read()
    term.setCursorPos(1, H)
    term.clearLine()
    return result
end

-- Drawing operations -------------------------------------------------------

-- Bresenham line algorithm
local function drawLineOnCanvas(x1, y1, x2, y2, color)
    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)
    local sx = x1 < x2 and 1 or -1
    local sy = y1 < y2 and 1 or -1
    local err = dx - dy
    local x, y = x1, y1
    while true do
        if x >= 1 and x <= CANVAS_W and y >= 1 and y <= CANVAS_H then
            state.canvas[y][x] = color
        end
        if x == x2 and y == y2 then break end
        local e2 = 2 * err
        if e2 > -dy then err = err - dy; x = x + sx end
        if e2 <  dx then err = err + dx; y = y + sy end
    end
end

-- Iterative flood fill (no stack overflow on large canvases)
local function floodFill(x, y, newColor)
    if x < 1 or x > CANVAS_W or y < 1 or y > CANVAS_H then return end
    local origColor = state.canvas[y][x]
    if origColor == newColor then return end
    local stack = { { x, y } }
    local visited = {}
    while #stack > 0 do
        local pos = table.remove(stack)
        local px, py = pos[1], pos[2]
        if px >= 1 and px <= CANVAS_W and py >= 1 and py <= CANVAS_H then
            local key = px .. "," .. py
            if not visited[key] then
                visited[key] = true
                if state.canvas[py][px] == origColor then
                    state.canvas[py][px] = newColor
                    table.insert(stack, { px + 1, py })
                    table.insert(stack, { px - 1, py })
                    table.insert(stack, { px, py + 1 })
                    table.insert(stack, { px, py - 1 })
                end
            end
        end
    end
end

-- Clear the entire canvas
local function clearCanvas()
    for y = 1, CANVAS_H do
        for x = 1, CANVAS_W do
            state.canvas[y][x] = nil
        end
    end
    state.status = "canvas cleared"
end

-- Apply a tool click at canvas coords (cx, cy)
local function applyTool(cx, cy)
    if cx < 1 or cx > CANVAS_W or cy < 1 or cy > CANVAS_H then return end
    local color = PALETTE[state.currentColor]
    if state.tool == "brush" then
        state.canvas[cy][cx] = color
        state.lineStart = nil
    elseif state.tool == "eraser" then
        state.canvas[cy][cx] = nil
        state.lineStart = nil
    elseif state.tool == "fill" then
        floodFill(cx, cy, color)
        state.lineStart = nil
    elseif state.tool == "line" then
        if not state.lineStart then
            state.lineStart = { cx, cy }
            state.status = "line start set; click endpoint"
        else
            drawLineOnCanvas(state.lineStart[1], state.lineStart[2], cx, cy, color)
            state.lineStart = nil
            state.status = ""
        end
    end
end

-- Rendering ----------------------------------------------------------------

local function renderCanvas()
    for y = 1, CANVAS_H do
        for x = 1, CANVAS_W do
            local c = state.canvas[y][x]
            if c then
                paintutils.drawPixel(x, y, c)
            else
                -- Transparent: show a checkerboard of black/gray
                if (x + y) % 2 == 0 then
                    paintutils.drawPixel(x, y, colors.black)
                else
                    paintutils.drawPixel(x, y, colors.gray)
                end
            end
        end
    end
end

local function renderPalette()
    -- Palette row sits just below the canvas
    local palY = CANVAS_H + 2
    local swatchW = 3
    for i, color in ipairs(PALETTE) do
        local x = (i - 1) * swatchW + 1
        if x + swatchW - 1 > W then break end
        paintutils.drawFilledBox(x, palY, x + swatchW - 1, palY, color)
        if i == state.currentColor then
            -- Selected: draw a yellow border above and below
            paintutils.drawBox(x, palY, x + swatchW - 1, palY, colors.yellow)
            term.setTextColor(colors.yellow)
            term.setBackgroundColor(colors.black)
            term.setCursorPos(x, palY - 1)
            term.write(" v ")
        end
    end
end

local function renderStatus()
    -- Status line at the very bottom
    term.setCursorPos(1, H)
    term.setTextColor(colors.black)
    term.setBackgroundColor(colors.lightGray)
    local tool = TOOL_NAMES[state.tool] or state.tool
    local colorName = "color " .. tostring(state.currentColor)
    local fname = state.filename or "(unsaved)"
    local status = string.format(" Tool:%-7s  Color:%-2d  File:%-20s  %s",
        tool, state.currentColor, fname:sub(1, 20),
        "b=brush e=eraser l=line f=fill s=save o=open c=clear q=quit")
    status = status .. string.rep(" ", math.max(0, W - #status))
    term.write(status:sub(1, W))
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

local function render()
    term.setBackgroundColor(colors.black)
    term.clear()
    renderCanvas()
    renderPalette()
    renderStatus()
    -- Show line-tool start marker
    if state.tool == "line" and state.lineStart then
        local sx, sy = state.lineStart[1], state.lineStart[2]
        if sx >= 1 and sx <= CANVAS_W and sy >= 1 and sy <= CANVAS_H then
            paintutils.drawPixel(sx, sy, colors.white)
        end
    end
    -- Message line (above the status bar)
    if state.status ~= "" then
        term.setCursorPos(1, H - 1)
        term.setTextColor(colors.yellow)
        term.setBackgroundColor(colors.black)
        term.write(state.status:sub(1, W))
    end
end

-- Main loop ----------------------------------------------------------------

local function main()
    -- If a file was given, load it
    if state.filename then
        loadFile(state.filename)
    end

    term.setCursorBlink(false)
    while true do
        render()
        local event = { os.pullEvent() }
        local ev = event[1]

        if ev == "key" then
            local key = event[2]
            if key == (keys and keys.q or 16) then
                break
            elseif key == (keys and keys.b or 48) then
                state.tool = "brush"; state.status = ""
            elseif key == (keys and keys.e or 18) then
                state.tool = "eraser"; state.status = ""
            elseif key == (keys and keys.l or 38) then
                state.tool = "line"; state.status = "click start point"
                state.lineStart = nil
            elseif key == (keys and keys.f or 33) then
                state.tool = "fill"; state.status = ""
            elseif key == (keys and keys.s or 31) then
                local path = state.filename
                if not path then
                    path = prompt("Save as: ")
                    if not path or path == "" then state.status = "aborted"
                    else state.filename = path end
                end
                if path and path ~= "" then saveFile(path) end
            elseif key == (keys and keys.o or 24) then
                local path = prompt("Open: ")
                if path and path ~= "" then loadFile(path) end
            elseif key == (keys and keys.c or 46) then
                clearCanvas()
            end
        elseif ev == "char" then
            local c = event[2]:lower()
            local slot = KEY_TO_SLOT[c]
            if slot then
                state.currentColor = slot
                state.status = ""
            end
        elseif ev == "mouse_click" then
            -- mouse_click: button, x, y
            local _, mx, my = event[2], event[3], event[4]
            applyTool(mx, my)
        elseif ev == "mouse_drag" then
            -- mouse_drag: button, x, y
            local _, mx, my = event[2], event[3], event[4]
            -- During drag, only brush/eraser continuously paint
            if state.tool == "brush" or state.tool == "eraser" then
                applyTool(mx, my)
            end
        elseif ev == "monitor_touch" and useMonitorTouch then
            -- monitor_touch: side, x, y
            local mx, my = event[3], event[4]
            applyTool(mx, my)
        end
    end

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    -- If we redirected to a monitor, restore the original term
    if monitorRedirect and term.redirect then
        -- term.redirect was already called above; we need to redirect
        -- back to the original. Since we don't have a saved reference,
        -- we redirect to term.native() if available, or just clear the
        -- monitor.
        if term.native then
            term.redirect(term.native())
        end
        monitorRedirect.clear()
        monitorRedirect.setCursorPos(1, 1)
    end
    return 0
end

return main()
