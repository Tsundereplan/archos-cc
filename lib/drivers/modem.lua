--[[
    lib/drivers/modem.lua  —  Modem (network) driver
    ===============================================
    Tracks attached modems (wired/wireless), opens channels, and forwards
    modem_message events to the Network library.
]]

local Modem = {}

Modem.attached = {}  -- side -> { wrap, isWireless, openChannels }
Modem.nextChannel = 1

function Modem.onAttach(side, wrap)
    if not wrap then wrap = peripheral.wrap(side) end
    local isWireless = wrap.isWireless and wrap.isWireless() or false
    Modem.attached[side] = {
        side = side,
        wrap = wrap,
        isWireless = isWireless,
        openChannels = {},
    }
    if _G.BIOS and _G.BIOS.log then
        _G.BIOS.log("[modem] Attached modem at " .. side .. " (" .. (isWireless and "wireless" or "wired") .. ")")
    end
    -- Initialize network if available
    if _G.Network and not _G.Network.online then
        pcall(_G.Network.init)
    end
end

function Modem.onDetach(side)
    if Modem.attached[side] then
        if _G.BIOS and _G.BIOS.log then
            _G.BIOS.log("[modem] Detached modem at " .. side)
        end
        Modem.attached[side] = nil
    end
end

function Modem.open(side, channel)
    local info = Modem.attached[side]
    if not info then return false, "no modem at " .. side end
    pcall(info.wrap.open, channel)
    info.openChannels[channel] = true
    return true
end

function Modem.close(side, channel)
    local info = Modem.attached[side]
    if not info then return false end
    pcall(info.wrap.close, channel)
    info.openChannels[channel] = nil
    return true
end

function Modem.closeAll(side)
    local info = Modem.attached[side]
    if not info then return false end
    for ch, _ in pairs(info.openChannels) do
        pcall(info.wrap.close, ch)
    end
    info.openChannels = {}
    return true
end

function Modem.transmit(side, channel, replyChannel, message)
    local info = Modem.attached[side]
    if not info then return false end
    pcall(info.wrap.transmit, channel, replyChannel, message)
    return true
end

-- Get the first available modem (wired or wireless preferred)
function Modem.primary(preferWireless)
    local wired, wireless
    for side, info in pairs(Modem.attached) do
        if info.isWireless then
            wireless = info
        else
            wired = info
        end
    end
    if preferWireless then
        return wireless or wired
    else
        return wired or wireless
    end
end

function Modem.list()
    local out = {}
    for side, info in pairs(Modem.attached) do
        table.insert(out, info)
    end
    table.sort(out, function(a, b) return a.side < b.side end)
    return out
end

-- Initialize from BIOS-detected hardware
function Modem.init(hw)
    if not hw or not hw.modems then return end
    for _, m in ipairs(hw.modems) do
        Modem.onAttach(m.side, m.wrap)
    end
end

return Modem
