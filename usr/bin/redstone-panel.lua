--[[
    usr/bin/redstone-panel.lua  —  Redstone Control Panel (GUI)
    ===========================================================
    Interactive panel to view and control redstone signals on
    all 6 sides (top/bottom/left/right/front/back).

    For each side shows:
      * Input strength (0-15) as a colored bar.
      * Output state (on/off) as a toggle button.
      * In bundled mode: 16-color bit field for individual channels.

    Hotkeys:
      Up/Dn/Left/Right : navigate between sides / channels
      Tab              : toggle between sides list and bundled channels
      Enter / Space    : toggle output for selected side (or channel bit in bundled mode)
      b                : toggle bundled mode
      r                : refresh display
      q                : quit
]]

local args = arg or {...}

-- bit32 helpers (CC:Tweaked provides bit32; Lua 5.1 compatible)
-- NOTE: do NOT use Lua 5.3 bitwise operators (&, |, ~, <<, >>) anywhere
-- in this file. CC:Tweaked uses Lua 5.1 (Cobalt) which doesn't parse them.
local bit = bit32 or {
    -- Arithmetic fallback (slow but correct) if bit32 is missing.
    band = function(a, b)
        local r, p = 0, 1
        for _ = 1, 32 do
            if a % 2 == 1 and b % 2 == 1 then r = r + p end
            a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2
        end
        return r
    end,
    bor = function(a, b)
        local r, p = 0, 1
        for _ = 1, 32 do
            if a % 2 == 1 or b % 2 == 1 then r = r + p end
            a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2
        end
        return r
    end,
    bxor = function(a, b)
        local r, p = 0, 1
        for _ = 1, 32 do
            if (a % 2) ~= (b % 2) then r = r + p end
            a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2
        end
        return r
    end,
    blshift = function(a, n) return (a * 2^n) % 4294967296 end,
    brshift = function(a, n) return math.floor(a / 2^n) % 4294967296 end,
}

-- Colour helpers
local function setFG(c) if term.isColor() then term.setTextColor(c) end end
local function setBG(c) if term.isColor() then term.setBackgroundColor(c) end end
local function resetColors()
    if term.isColor() then
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
    end
end

-- Box-drawing characters
local BOX_TL, BOX_TR, BOX_BL, BOX_BR = "+", "+", "+", "+"
local BOX_H,  BOX_V                   = "=", "|"
local BLK_ON, BLK_OFF                 = "#", "."

local function writeAt(x, y, s)
    term.setCursorPos(x, y)
    term.write(s)
end

-- The 16 colors matching ComputerCraft colors API bit values.
-- (colors.white=1, colors.orange=2, colors.magenta=4, ...)
local COLOR_CHANNELS = {
    { name = "white",      bit = colors.white },
    { name = "orange",     bit = colors.orange },
    { name = "magenta",    bit = colors.magenta },
    { name = "lightBlue",  bit = colors.lightBlue },
    { name = "yellow",     bit = colors.yellow },
    { name = "lime",       bit = colors.lime },
    { name = "pink",       bit = colors.pink },
    { name = "gray",       bit = colors.gray },
    { name = "lightGray",  bit = colors.lightGray },
    { name = "cyan",       bit = colors.cyan },
    { name = "purple",    bit = colors.purple },
    { name = "blue",       bit = colors.blue },
    { name = "brown",      bit = colors.brown },
    { name = "green",      bit = colors.green },
    { name = "red",        bit = colors.red },
    { name = "black",      bit = colors.black },
}

local SIDES = {"top","bottom","left","right","front","back"}

-- State
local state = {
    selected = 1,         -- side index
    bundledMode = false,
    selectedChannel = 1,  -- channel index when bundledMode
    -- cached values
    inputs  = {},   -- side -> strength 0-15
    outputs = {},   -- side -> bool
    bundledOutputs = {},  -- side -> bitfield int
    bundledInputs  = {},  -- side -> bitfield int
    message = "",
    msgTime = 0,
}

local function msg(s)
    state.message = s
    state.msgTime = os.clock()
end

-- Determine if bundled cable support is available on a side
-- (CC:T returns 0 if no bundled cable is connected; we still allow setting.)
local function rsAPI()
    -- CC:Tweaked exposes both `redstone` and `rs`; they're identical.
    return redstone or rs
end

local function refreshSide(sideIdx)
    local rs = rsAPI()
    if not rs then return end
    local side = SIDES[sideIdx]
    -- input strength (0-15) - testBundledInput gives analog strength of any color
    state.inputs[sideIdx]  = rs.getInput(side) and 15 or 0
    state.outputs[sideIdx] = rs.getOutput(side) or false
    state.bundledOutputs[sideIdx] = rs.getBundledOutput(side) or 0
    state.bundledInputs[sideIdx]  = rs.getBundledInput(side) or 0
end

local function refreshAll()
    for i = 1, #SIDES do refreshSide(i) end
end

---------------------------------------------------------------- rendering ---

local function strengthBar(strength, w)
    -- returns a colored bar string for input strength 0-15
    local filled = math.floor(strength / 15 * w + 0.5)
    if filled > w then filled = w end
    if filled < 0 then filled = 0 end
    local bar = string.rep(BLK_ON, filled) .. string.rep(BLK_OFF, w - filled)
    return bar
end

local function renderSidePanel(idx, x, y, w, isSelected)
    local rs = rsAPI()
    if not rs then
        if term.isColor() then term.setTextColor(colors.red) end
        writeAt(x, y, "Redstone API unavailable")
        resetColors()
        return
    end
    local side = SIDES[idx]
    local strength = state.inputs[idx] or 0
    local out = state.outputs[idx]
    local bo  = state.bundledOutputs[idx] or 0
    local bi  = state.bundledInputs[idx] or 0

    -- panel box
    if isSelected then
        setBG(colors.blue); setFG(colors.white)
    end
    -- Draw 4-row panel
    local rows = {
        " " .. side .. string.rep(" ", math.max(0, w - 2 - #side)),
        " In  :" .. strengthBar(strength, w - 7),
        " Out :" .. (out and BLK_ON or BLK_OFF) .. " " .. (out and "ON " or "OFF"),
    }
    if state.bundledMode then
        -- show bundled output bitmask
        rows[4] = string.format(" Bndl:0x%04X (in 0x%04X)", bo, bi)
    else
        rows[4] = string.format(" Analog:%2d/15", strength)
    end

    for i, line in ipairs(rows) do
        if isSelected then
            setBG(colors.blue); setFG(colors.white)
        else
            setBG(colors.black); setFG(colors.lightGray)
        end
        -- pad
        line = line .. string.rep(" ", math.max(0, w - #line))
        writeAt(x, y + i - 1, line:sub(1, w))
        resetColors()
    end
end

local function renderBundledChannels(idx, x, y, w, h)
    -- show 16 channels in a 4x4 grid for side `idx`
    local rs = rsAPI()
    local bo = state.bundledOutputs[idx] or 0
    local bi = state.bundledInputs[idx] or 0
    local side = SIDES[idx]

    writeAt(x, y, "Bundled I/O for " .. side .. ":")
    writeAt(x, y + 1, string.format("Output: 0x%04X   Input: 0x%04X", bo, bi))

    -- 4x4 grid of channels
    local gridX = x
    local gridY = y + 3
    local cellW = math.max(14, math.floor((w - 4) / 4))
    for i, ch in ipairs(COLOR_CHANNELS) do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        local cx = gridX + col * cellW
        local cy = gridY + row * 2
        if cy + 1 > y + h - 1 then break end

        local outBit = (bit.band(bo, ch.bit) ~= 0)
        local inBit  = (bit.band(bi, ch.bit) ~= 0)
        local selected = (state.selectedChannel == i)

        -- draw cell box
        if selected then
            setBG(colors.blue); setFG(colors.white)
        else
            setBG(colors.black); setFG(ch.bit ~= 0 and ch.bit or colors.white)
        end
        -- color block (use channel color background)
        local oldBG = term.isColor() and term.setBackgroundColor(colors.black)
        -- header row: color name + colored block
        if term.isColor() then
            term.setBackgroundColor(colors.black)
            term.setTextColor(ch.bit)
        end
        writeAt(cx, cy, string.format(" %-11s", ch.name:sub(1, 11)))
        -- status row: in/out indicator
        if selected then
            setBG(colors.blue); setFG(colors.white)
        else
            setBG(colors.black); setFG(colors.lightGray)
        end
        local status = string.format(" out:%s in:%s", outBit and "1" or "0", inBit and "1" or "0")
        writeAt(cx, cy + 1, status)
        resetColors()
    end
end

local function render()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()

    -- Title bar
    setBG(colors.blue); setFG(colors.white)
    writeAt(1, 1, " ArchOS-CC Redstone Control Panel")
    if state.bundledMode then
        term.write(" [BUNDLED]")
    end
    term.write(string.rep(" ", math.max(0, w - term.getCursorPos())))
    -- pad to width
    local cx = term.getCursorPos()
    writeAt(cx, 1, string.rep(" ", w - cx))
    resetColors()

    -- Mode hint
    setFG(colors.yellow)
    writeAt(1, 2, string.format(" Mode: %-9s   Selected side: %-8s",
        state.bundledMode and "BUNDLED" or "ANALOG", SIDES[state.selected]))
    resetColors()

    -- Layout: 3x2 grid of side panels (top, left, right on top row;
    -- front, bottom, back on bottom row)
    local panelW = math.max(20, math.floor((w - 4) / 3))
    local panelH = 4
    -- Side positions (3 columns x 2 rows)
    local positions = {
        [1] = { x = 2,                       y = 4 },  -- top
        [2] = { x = 2,                       y = 4 + panelH + 2 }, -- bottom
        [3] = { x = 2 + panelW + 1,          y = 4 },  -- left
        [4] = { x = 2 + 2*(panelW + 1),     y = 4 },  -- right
        [5] = { x = 2 + panelW + 1,          y = 4 + panelH + 2 }, -- front
        [6] = { x = 2 + 2*(panelW + 1),     y = 4 + panelH + 2 }, -- back
    }

    -- Draw divider lines for clarity
    setFG(colors.gray)
    writeAt(1, 4 + panelH + 1, string.rep(BOX_H, w))
    resetColors()

    for i = 1, #SIDES do
        local p = positions[i]
        renderSidePanel(i, p.x, p.y, panelW, i == state.selected)
    end

    -- Bundled channels section
    if state.bundledMode then
        local chanY = 4 + 2*(panelH + 2) - 2
        if chanY < h - 6 then
            renderBundledChannels(state.selected, 2, chanY, w, h)
        end
    end

    -- Footer / hotkey bar
    setBG(colors.lightGray); setFG(colors.black)
    writeAt(1, h, " Arrows=navigate  Enter=toggle  b=bundled  r=refresh  q=quit")
    local bar = " Arrows=navigate  Enter=toggle  b=bundled  r=refresh  q=quit"
    if state.message ~= "" and (os.clock() - state.msgTime) < 2.5 then
        bar = " " .. state.message
    end
    bar = bar .. string.rep(" ", math.max(0, w - #bar))
    writeAt(1, h, bar:sub(1, w))
    resetColors()

    -- current selected side summary
    local idx = state.selected
    setFG(colors.cyan)
    local selInfo = string.format(" [%s]  In: %2d/15  Out: %-3s  Bundled out: 0x%04X",
        SIDES[idx], state.inputs[idx] or 0,
        (state.outputs[idx] and "ON" or "OFF"),
        state.bundledOutputs[idx] or 0)
    writeAt(1, h - 1, selInfo:sub(1, w))
    resetColors()
end

---------------------------------------------------------------- actions ---

local function toggleOutput()
    local rs = rsAPI()
    if not rs then return end
    local idx = state.selected
    if state.bundledMode then
        -- toggle the selected channel's bit
        local ch = COLOR_CHANNELS[state.selectedChannel]
        local current = state.bundledOutputs[idx] or 0
        local new
        if bit.band(current, ch.bit) ~= 0 then
            new = bit.band(current, bit.bxor(ch.bit, 0xFFFFFFFF))  -- clear bit
            -- mask to 16 bits (CC:T bundled is 16-bit)
            new = bit.band(new, 0xFFFF)
        else
            new = bit.bor(current, ch.bit)
        end
        rs.setBundledOutput(SIDES[idx], new)
        msg("Channel " .. ch.name .. " toggled on " .. SIDES[idx])
    else
        local newState = not state.outputs[idx]
        rs.setOutput(SIDES[idx], newState)
        msg(SIDES[idx] .. " output " .. (newState and "ON" or "OFF"))
    end
    refreshSide(idx)
end

local function navigate(dx, dy)
    if state.bundledMode then
        -- navigate 4x4 grid of channels
        local col = (state.selectedChannel - 1) % 4
        local row = math.floor((state.selectedChannel - 1) / 4)
        col = (col + dx) % 4
        if col < 0 then col = col + 4 end
        row = (row + dy) % 4
        if row < 0 then row = row + 4 end
        state.selectedChannel = row * 4 + col + 1
    else
        -- navigate 3x2 grid of sides
        -- mapping: 1=top   (col 0, row 0)
        --          3=left  (col 1, row 0)
        --          4=right (col 2, row 0)
        --          2=bottom(col 0, row 1)
        --          5=front (col 1, row 1)
        --          6=back  (col 2, row 1)
        local grid = {
            [1] = { 0, 0 }, [3] = { 1, 0 }, [4] = { 2, 0 },
            [2] = { 0, 1 }, [5] = { 1, 1 }, [6] = { 2, 1 },
        }
        local reverseGrid = {}
        for k, v in pairs(grid) do reverseGrid[v[1] * 10 + v[2]] = k end
        local cur = grid[state.selected]
        if cur then
            local newCol = (cur[1] + dx) % 3
            if newCol < 0 then newCol = newCol + 3 end
            local newRow = (cur[2] + dy) % 2
            if newRow < 0 then newRow = newRow + 2 end
            local newIdx = reverseGrid[newCol * 10 + newRow]
            if newIdx then state.selected = newIdx end
        end
    end
end

---------------------------------------------------------------- main ---

local function main()
    -- initial data load
    refreshAll()
    -- auto-refresh timer
    local refreshTimer = os.startTimer(1)

    while true do
        render()
        local event = { os.pullEvent() }
        local ev = event[1]

        if ev == "timer" and event[2] == refreshTimer then
            refreshAll()
            refreshTimer = os.startTimer(1)
        elseif ev == "redstone" then
            -- a redstone input changed somewhere; refresh all
            refreshAll()
        elseif ev == "key" then
            local key = event[2]
            if key == keys.q then
                break
            elseif key == keys.up then
                navigate(0, -1)
            elseif key == keys.down then
                navigate(0, 1)
            elseif key == keys.left then
                navigate(-1, 0)
            elseif key == keys.right then
                navigate(1, 0)
            elseif key == keys.enter or key == keys.space then
                toggleOutput()
            elseif key == keys.tab then
                -- in bundled mode, tab moves to channel grid (already showing)
                -- here it's a no-op since we always show channels in bundled mode
                msg("Tab focus n/a")
            end
        elseif ev == "char" then
            local c = event[2]:lower()
            if c == "q" then break
            elseif c == "b" then
                state.bundledMode = not state.bundledMode
                msg("Bundled mode: " .. (state.bundledMode and "ON" or "OFF"))
            elseif c == "r" then
                refreshAll()
                msg("Refreshed")
            end
        end
    end

    resetColors()
    term.clear()
    term.setCursorPos(1, 1)
    return 0
end

return main()
