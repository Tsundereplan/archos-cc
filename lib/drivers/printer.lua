--[[
    lib/drivers/printer.lua  —  Printer driver
    =========================================
    Tracks attached printers, queues print jobs, supports multi-page output.
]]

local Printer = {}

Printer.attached = {}  -- side -> { wrap, busy, paperLevel, inkLevel }

function Printer.onAttach(side, wrap)
    if not wrap then wrap = peripheral.wrap(side) end
    Printer.attached[side] = {
        side = side,
        wrap = wrap,
        busy = false,
    }
    if _G.BIOS and _G.BIOS.log then
        _G.BIOS.log("[printer] Attached printer at " .. side)
    end
end

function Printer.onDetach(side)
    if Printer.attached[side] then
        if _G.BIOS and _G.BIOS.log then
            _G.BIOS.log("[printer] Detached printer at " .. side)
        end
        Printer.attached[side] = nil
    end
end

-- Get status: paper level, ink level
function Printer.status(side)
    local info = Printer.attached[side]
    if not info then return nil end
    return {
        paperLevel = info.wrap.getPaperLevel and info.wrap.getPaperLevel() or 0,
        inkLevel = info.wrap.getInkLevel and info.wrap.getInkLevel() or 0,
    }
end

-- Print a string (possibly multi-line, paginated)
function Printer.print(side, text, title)
    local info = Printer.attached[side]
    if not info then return false, "no printer at " .. side end
    if info.busy then return false, "printer busy" end
    info.busy = true

    local wrap = info.wrap
    -- Start a new page
    if not wrap.newPage then return false, "printer doesn't support pages" end
    if not wrap.newPage() then
        info.busy = false
        return false, "cannot start page (out of paper/ink?)"
    end

    -- Optional title
    if title then
        wrap.setCursorPos(1, 1)
        wrap.write(title)
        wrap.setCursorPos(1, 3)
    else
        wrap.setCursorPos(1, 1)
    end

    -- Write each line
    local lines = {}
    for line in text:gmatch("[^\n]*") do
        table.insert(lines, line)
    end
    local page = 1
    local h = wrap.getPageSize and wrap.getPageSize() or 21
    local y = select(2, wrap.getCursorPos())
    for i, line in ipairs(lines) do
        if y > h then
            -- End this page, start new
            wrap.endPage()
            page = page + 1
            if not wrap.newPage() then
                info.busy = false
                return false, "out of paper at page " .. page
            end
            wrap.setCursorPos(1, 1)
            y = 1
        end
        wrap.write(line)
        wrap.setCursorPos(1, y + 1)
        y = y + 1
    end
    wrap.endPage()
    info.busy = false
    return true, page
end

function Printer.list()
    local out = {}
    for side, info in pairs(Printer.attached) do
        table.insert(out, info)
    end
    table.sort(out, function(a, b) return a.side < b.side end)
    return out
end

function Printer.init(hw)
    if not hw or not hw.printers then return end
    for _, wrap in ipairs(hw.printers) do
        -- Need to find the side
        for _, side in ipairs({"top", "bottom", "left", "right", "front", "back"}) do
            if peripheral.getType(side) == "printer" and peripheral.wrap(side) == wrap then
                Printer.onAttach(side, wrap)
                break
            end
        end
    end
end

return Printer
