--[[
    lib/drivers/pnp.lua  —  Plug-and-Play manager
    =============================================
    Subscribes to peripheral_attach/peripheral_detach and disk/disk_eject
    events. Maintains a hot-pluggable device table and notifies other
    drivers (disk, monitor, modem, etc.) when devices appear/disappear.
]]

local PnP = {}

PnP.devices = {}     -- side -> {type, wrap, timestamp}
PnP.drivers = {}     -- type -> driver table
PnP.history = {}     -- recent events for dmesg

function PnP.log(msg)
    if _G.BIOS and _G.BIOS.log then
        _G.BIOS.log("[PnP] " .. msg)
    end
    table.insert(PnP.history, os.time() .. " " .. msg)
    if #PnP.history > 50 then table.remove(PnP.history, 1) end
end

-- Register a driver for a peripheral type
function PnP.registerDriver(peripheralType, driverTable)
    PnP.drivers[peripheralType] = driverTable
    PnP.log("Registered driver for: " .. peripheralType)
end

-- Initialize PnP with the BIOS hw table
function PnP.init(hw)
    PnP.hw = hw or {}
    -- Pre-register built-in drivers
    local ok
    ok, _ = pcall(function()
        local disk = dofile("/lib/drivers/disk.lua")
        PnP.registerDriver("drive", disk)
    end)
    ok, _ = pcall(function()
        local mon = dofile("/lib/drivers/monitor.lua")
        PnP.registerDriver("monitor", mon)
    end)
    ok, _ = pcall(function()
        local mod = dofile("/lib/drivers/modem.lua")
        PnP.registerDriver("modem", mod)
    end)
    ok, _ = pcall(function()
        local prt = dofile("/lib/drivers/printer.lua")
        PnP.registerDriver("printer", prt)
    end)
    ok, _ = pcall(function()
        local spk = dofile("/lib/drivers/speaker.lua")
        PnP.registerDriver("speaker", spk)
    end)

    -- Subscribe to attach/detach events
    if _G.Events then
        _G.Events.subscribe("peripheral", function(side, peripheralType)
            PnP.onAttach(side, peripheralType)
        end)
        _G.Events.subscribe("peripheral_detach", function(side)
            PnP.onDetach(side)
        end)
        _G.Events.subscribe("disk", function(side)
            PnP.onDiskInsert(side)
        end)
        _G.Events.subscribe("disk_eject", function(side)
            PnP.onDiskEject(side)
        end)
    end

    PnP.log("PnP subsystem initialized")
end

-- Device attach handler
function PnP.onAttach(side, peripheralType)
    PnP.log("Attached: " .. side .. " (" .. peripheralType .. ")")
    local wrap = peripheral.wrap(side)
    PnP.devices[side] = {
        side = side,
        type = peripheralType,
        wrap = wrap,
        attachedAt = os.time(),
    }
    -- Notify the driver for this type
    local driver = PnP.drivers[peripheralType]
    if driver and driver.onAttach then
        local ok, err = pcall(driver.onAttach, side, wrap)
        if not ok then PnP.log("Driver error: " .. tostring(err)) end
    end
    -- Dispatch system event
    if _G.Events then
        _G.Events.dispatch("archos_device_attach", side, peripheralType)
    end
end

function PnP.onDetach(side)
    local info = PnP.devices[side]
    if info then
        PnP.log("Detached: " .. side .. " (" .. info.type .. ")")
        local driver = PnP.drivers[info.type]
        if driver and driver.onDetach then
            pcall(driver.onDetach, side)
        end
        PnP.devices[side] = nil
    else
        PnP.log("Detached: " .. side .. " (unknown)")
    end
    if _G.Events then
        _G.Events.dispatch("archos_device_detach", side)
    end
end

function PnP.onDiskInsert(side)
    PnP.log("Disk inserted in drive " .. side)
    local driver = PnP.drivers["drive"]
    if driver and driver.onDiskInsert then
        pcall(driver.onDiskInsert, side)
    end
    if _G.Events then
        _G.Events.dispatch("archos_disk_insert", side)
    end
end

function PnP.onDiskEject(side)
    PnP.log("Disk ejected from drive " .. side)
    local driver = PnP.drivers["drive"]
    if driver and driver.onDiskEject then
        pcall(driver.onDiskEject, side)
    end
    if _G.Events then
        _G.Events.dispatch("archos_disk_eject", side)
    end
end

-- List all currently attached devices
function PnP.listDevices()
    local out = {}
    for side, info in pairs(PnP.devices) do
        table.insert(out, info)
    end
    table.sort(out, function(a, b) return a.side < b.side end)
    return out
end

-- Get device by side
function PnP.getDevice(side)
    return PnP.devices[side]
end

-- Find first device of a given type
function PnP.findDevice(peripheralType)
    for side, info in pairs(PnP.devices) do
        if info.type == peripheralType then
            return side, info
        end
    end
    return nil
end

return PnP
