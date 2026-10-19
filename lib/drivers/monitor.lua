--[[
    lib/drivers/monitor.lua  —  Monitor driver
    =========================================
    Tracks attached monitors and provides:
      * Window objects for each monitor
      * Auto-detection of advanced (color) vs basic monitors
      * Resize event handling
      * Multi-monitor support (you can attach several)
]]

local Monitor = {}

-- Map: side -> { wrap, width, height, advanced, redirectObj }
Monitor.attached = {}

function Monitor.onAttach(side, wrap)
    if not wrap then wrap = peripheral.wrap(side) end
    local w, h = wrap.getSize()
    local advanced = wrap.isColor and wrap.isColor() or false
    Monitor.attached[side] = {
        side = side,
        wrap = wrap,
        width = w,
        height = h,
        advanced = advanced,
        redirect = wrap, -- The monitor itself is a terminal redirect
    }
    if _G.BIOS and _G.BIOS.log then
        _G.BIOS.log("[monitor] Attached monitor at " .. side .. " (" .. w .. "x" .. h .. ", " .. (advanced and "color" or "mono") .. ")")
    end
end

function Monitor.onDetach(side)
    if Monitor.attached[side] then
        if _G.BIOS and _G.BIOS.log then
            _G.BIOS.log("[monitor] Detached monitor at " .. side)
        end
        Monitor.attached[side] = nil
    end
end

-- Find the primary monitor (first attached, or by name)
function Monitor.primary()
    for side, info in pairs(Monitor.attached) do
        return side, info
    end
    return nil
end

-- Get a monitor by side
function Monitor.get(side)
    return Monitor.attached[side]
end

-- List all attached monitors
function Monitor.list()
    local out = {}
    for side, info in pairs(Monitor.attached) do
        table.insert(out, info)
    end
    table.sort(out, function(a, b) return a.side < b.side end)
    return out
end

-- Write text to a monitor
function Monitor.write(side, text)
    local info = Monitor.attached[side]
    if not info then return false end
    local oldTerm = term.redirect(info.wrap)
    term.write(text)
    term.redirect(oldTerm)
    return true
end

-- Clear a monitor
function Monitor.clear(side)
    local info = Monitor.attached[side]
    if not info then return false end
    info.wrap.clear()
    info.wrap.setCursorPos(1, 1)
    return true
end

-- Handle resize event
function Monitor.onResize(side)
    local info = Monitor.attached[side]
    if info then
        local w, h = info.wrap.getSize()
        info.width = w
        info.height = h
        if _G.BIOS and _G.BIOS.log then
            _G.BIOS.log("[monitor] Resized monitor at " .. side .. " to " .. w .. "x" .. h)
        end
    end
end

-- Create a window on a monitor at a specific area
function Monitor.createWindow(side, x, y, width, height)
    local info = Monitor.attached[side]
    if not info then return nil end
    -- Use CC:Tweaked's window API
    local window = window.create(info.wrap, x, y, width, height, false)
    return window
end

-- Initialize from BIOS-detected hardware
function Monitor.init(hw)
    if not hw or not hw.monitors then return end
    for side, wrap in pairs(hw.monitors) do
        Monitor.onAttach(side, wrap)
    end
end

return Monitor
