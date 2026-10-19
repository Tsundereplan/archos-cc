-- bin/poweroff.lua  —  Power off (shutdown) the system
-- Usage: poweroff

local Kernel = _G.Kernel
local Events = _G.Events

-- -- Only root may power off -------------------------------------------------
if Kernel and Kernel.getuid and Kernel.getuid() ~= 0 then
    io.stderr:write("poweroff: must be root\n")
    return 1
end

-- -- Dispatch a SHUTDOWN event so services can flush/cleanup ------------------
if Events and Events.TYPES and Events.dispatch then
    pcall(Events.dispatch, Events.TYPES.SHUTDOWN)
end

-- -- Announce, then call CC:Tweaked's os.shutdown() --------------------------
if term and term.isColor() then term.setTextColor(colors.yellow) end
print("Powering off...")
if term and term.isColor() then term.setTextColor(colors.white) end

-- Give listeners/scheduler a brief moment to flush before the hard shutdown
pcall(os.sleep, 0.1)

os.shutdown()

-- os.shutdown() never returns; if it ever does, treat as failure
return 0
