-- /sbin/mountd.lua  —  Mount daemon
-- Listens for peripheral_attach events and auto-mounts drives/cds.
-- Also handles disk insertion/ejection events.

local Events = _G.Events
local PnP = _G.Drivers and _G.Drivers.pnp

if not PnP and fs.exists("/lib/drivers/pnp.lua") then
    PnP = dofile("/lib/drivers/pnp.lua")
end
if not Events then
    print("mountd: events system not available")
    return 1
end

print("[mountd] Starting mount daemon ...")

-- Subscribe to PnP attach events
Events.subscribe("archos_device_attach", function(side, peripheralType)
    if peripheralType == "drive" then
        print("[mountd] Drive attached at " .. side)
    end
end)

Events.subscribe("archos_disk_insert", function(side)
    print("[mountd] Disk inserted in drive " .. side)
    -- Auto-mount handled by disk driver via PnP
end)

Events.subscribe("archos_disk_eject", function(side)
    print("[mountd] Disk ejected from drive " .. side)
end)

-- Loop forever
while true do os.sleep(1) end
