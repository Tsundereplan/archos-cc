-- usr/bin/calculator.lua  —  Simple calculator GUI
-- Click buttons or use keyboard. Supports + - * / and parentheses.
-- C clears, Backspace deletes the last character.

local paintutils = paintutils

if not term.isColor or not term.isColor() then
    io.stderr:write("calculator: requires a color display\n")
    return 1
end

-- Calculator state
local state = {
    expr   = "",
    result = "0",
    error  = nil,
}

-- Button layout: 4 columns x 4 rows of arithmetic buttons,
-- plus a 5th row with C and Backspace spanning two columns each.
local function makeButton(x, y, w, h, label, kind, value)
    return { x = x, y = y, w = w, h = h, label = label, kind = kind, value = value }
end

-- 4-wide column layout: buttons are 9 wide with 1-char gutters
-- On a 51-wide screen: 4 * 9 + 5 = 41, leaving 5 chars padding on each side.
local BX = 6   -- leftmost column start
local BW = 9   -- button width
local BH = 3   -- button height
local BG = 1   -- gutter
local function colX(c) return BX + (c - 1) * (BW + BG) end
local function rowY(r) return 5 + (r - 1) * (BH + BG) end

local buttons = {
    -- Row 1: digits 7 8 9 and /
    makeButton(colX(1), rowY(1), BW, BH, "7", "digit", "7"),
    makeButton(colX(2), rowY(1), BW, BH, "8", "digit", "8"),
    makeButton(colX(3), rowY(1), BW, BH, "9", "digit", "9"),
    makeButton(colX(4), rowY(1), BW, BH, "/", "op",    "/"),
    -- Row 2
    makeButton(colX(1), rowY(2), BW, BH, "4", "digit", "4"),
    makeButton(colX(2), rowY(2), BW, BH, "5", "digit", "5"),
    makeButton(colX(3), rowY(2), BW, BH, "6", "digit", "6"),
    makeButton(colX(4), rowY(2), BW, BH, "*", "op",    "*"),
    -- Row 3
    makeButton(colX(1), rowY(3), BW, BH, "1", "digit", "1"),
    makeButton(colX(2), rowY(3), BW, BH, "2", "digit", "2"),
    makeButton(colX(3), rowY(3), BW, BH, "3", "digit", "3"),
    makeButton(colX(4), rowY(3), BW, BH, "-", "op",    "-"),
    -- Row 4
    makeButton(colX(1), rowY(4), BW, BH, "0", "digit", "0"),
    makeButton(colX(2), rowY(4), BW, BH, ".", "dot",   "."),
    makeButton(colX(3), rowY(4), BW, BH, "=", "equals","="),
    makeButton(colX(4), rowY(4), BW, BH, "+", "op",    "+"),
    -- Row 5: C and Backspace (wider)
    makeButton(colX(1), rowY(5), BW * 2 + BG, BH, "C",  "clear", "C"),
    makeButton(colX(3), rowY(5), BW * 2 + BG, BH, "<-", "back",  "<-"),
}

-- Button colors by kind
local function buttonColor(b)
    if b.kind == "digit" then return colors.gray
    elseif b.kind == "op"     then return colors.orange
    elseif b.kind == "equals" then return colors.green
    elseif b.kind == "clear"  then return colors.red
    elseif b.kind == "back"   then return colors.purple
    elseif b.kind == "dot"    then return colors.lightGray
    else return colors.gray end
end

-- Find the button at a screen coordinate
local function findButton(x, y)
    for _, b in ipairs(buttons) do
        if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
            return b
        end
    end
    return nil
end

-- Safe arithmetic evaluation
local function evaluate(expr)
    if expr == nil or expr == "" then return "0", nil end
    -- Only allow digits, operators, parens, dot, spaces
    if not expr:match("^[0-9%+%-%*/%(%)%. ]+$") then
        return nil, "invalid characters"
    end
    local fn
    if setfenv then
        -- Lua 5.1 / CC:Tweaked: loadstring + setfenv
        fn = (loadstring or load)("return " .. expr)
        if fn then setfenv(fn, { math = math }) end
    else
        -- Lua 5.2+: load with environment argument
        fn = load("return " .. expr, "=calc", "t", { math = math })
    end
    if not fn then return nil, "syntax error" end
    local ok, result = pcall(fn)
    if not ok then return nil, "evaluation error" end
    if result == math.huge or result == -math.huge then
        return nil, "division by zero"
    end
    if result ~= result then
        return nil, "undefined"
    end
    -- Format integer results without trailing .0
    if type(result) == "number" and result == math.floor(result) then
        return tostring(math.floor(result)), nil
    end
    return tostring(result), nil
end

-- Apply a button press
local function applyButton(b)
    state.error = nil
    if b.kind == "digit" then
        state.expr = state.expr .. b.value
    elseif b.kind == "dot" then
        -- Avoid double-dots in the same number
        local lastNum = state.expr:match("[%d%.]+$") or ""
        if not lastNum:find("%.") then
            if lastNum == "" then
                state.expr = state.expr .. "0."
            else
                state.expr = state.expr .. "."
            end
        end
    elseif b.kind == "op" then
        -- Auto-continue from previous result if expr is empty
        if state.expr == "" and state.result and state.result ~= "0" then
            state.expr = state.result .. b.value
        else
            -- Don't allow two operators in a row; replace the last
            if state.expr:sub(-1):match("[%+%-%*/]") then
                state.expr = state.expr:sub(1, -2) .. b.value
            else
                state.expr = state.expr .. b.value
            end
        end
    elseif b.kind == "equals" then
        local r, err = evaluate(state.expr)
        if err then
            state.error = err
        else
            state.result = r
            state.expr = ""  -- ready for a new entry, but result preserved for chaining
        end
    elseif b.kind == "clear" then
        state.expr = ""
        state.result = "0"
    elseif b.kind == "back" then
        state.expr = state.expr:sub(1, -2)
    end
end

-- Apply a single character from keyboard input
local function applyChar(c)
    if c:match("[0-9]") then
        applyButton({ kind = "digit", value = c })
    elseif c == "." then
        applyButton({ kind = "dot" })
    elseif c:match("[%+%-%*/]") then
        applyButton({ kind = "op", value = c })
    elseif c == "=" or c == "\r" or c == "\n" then
        applyButton({ kind = "equals" })
    elseif c:lower() == "c" then
        applyButton({ kind = "clear" })
    end
end

-- Rendering ----------------------------------------------------------------

local function renderButton(b)
    local c = buttonColor(b)
    -- Filled block
    paintutils.drawFilledBox(b.x, b.y, b.x + b.w - 1, b.y + b.h - 1, c)
    -- Border (subtle)
    paintutils.drawBox(b.x, b.y, b.x + b.w - 1, b.y + b.h - 1, colors.lightGray)
    -- Centered label
    term.setTextColor(colors.white)
    term.setBackgroundColor(c)
    local lx = b.x + math.floor((b.w - #b.label) / 2)
    local ly = b.y + math.floor(b.h / 2)
    term.setCursorPos(lx, ly)
    term.write(b.label)
end

local function render()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()

    -- Title bar
    term.setCursorPos(1, 1)
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.blue)
    local title = " ArchOS Calculator "
    title = title .. string.rep(" ", math.max(0, w - #title))
    term.write(title:sub(1, w))
    term.setBackgroundColor(colors.black)

    -- Display: expression (top) and result (bottom)
    local dispX = BX
    local dispW = 4 * BW + 3 * BG  -- matches button grid width
    -- Frame
    paintutils.drawBox(dispX, 2, dispX + dispW - 1, 4, colors.lightGray)
    -- Expression line
    term.setCursorPos(dispX + 1, 2)
    term.setTextColor(colors.lightGray)
    term.setBackgroundColor(colors.black)
    term.write("expr:")
    term.setCursorPos(dispX + 1, 3)
    term.setTextColor(colors.white)
    local exprText = state.expr
    if exprText == "" then exprText = " " end
    term.write(exprText:sub(-(dispW - 2)))
    -- Result line
    term.setCursorPos(dispX + 1, 4)
    if state.error then
        term.setTextColor(colors.red)
        term.write("ERR: " .. state.error)
    else
        term.setTextColor(colors.green)
        term.write("= " .. state.result)
    end

    -- Render all buttons
    for _, b in ipairs(buttons) do
        renderButton(b)
    end

    -- Footer hint
    term.setCursorPos(1, h)
    term.setTextColor(colors.gray)
    term.setBackgroundColor(colors.black)
    local hint = " Type digits/operators or click buttons.  C=clear  Backspace=delete  Esc=quit "
    term.write(hint:sub(1, w))
end

-- Main loop ----------------------------------------------------------------

local function main()
    term.setCursorBlink(false)
    while true do
        render()
        local event = { os.pullEvent() }
        local ev = event[1]

        if ev == "key" then
            local key = event[2]
            if key == (keys and keys.escape or 1)
               or key == (keys and keys.q or 16) then
                break
            elseif key == (keys and keys.backspace or 14) then
                applyButton({ kind = "back" })
            elseif key == (keys and keys.enter or 28) then
                applyButton({ kind = "equals" })
            end
        elseif ev == "char" then
            local c = event[2]
            if c:lower() == "q" then
                -- q quits (avoids conflict: C clears, q quits)
                break
            else
                applyChar(c)
            end
        elseif ev == "mouse_click" then
            local _, mx, my = event[2], event[3], event[4]
            local b = findButton(mx, my)
            if b then applyButton(b) end
        end
    end

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    return 0
end

return main()
