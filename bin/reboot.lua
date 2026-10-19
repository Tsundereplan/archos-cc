-- bin/reboot.lua  —  Reboot the system
-- Usage: reboot

local Kernel = _G.Kernel
local Events = _G.Events

-- -- Only root may reboot ----------------------------------------------------
if Kernel and Kernel.getuid and Kernel.getuid() ~= 0 then
    io.stderr:write("reboot: must be root\n")
    return 1
end

-- -- Dispatch a REBOOT event so services can hook into a clean shutdown ------
if Events and Events.TYPES and Events.dispatch then
    pcall(Events.dispatch, Events.TYPES.REBOOT)
end

-- -- Announce, then call CC:Tweaked's os.reboot() ----------------------------
if term and term.isColor() then term.setTextColor(colors.yellow) end
print("Rebooting...")
if term and term.isColor() then term.setTextColor(colors.white) end

-- Give listeners/scheduler a brief moment to flush before the hard reboot
pcall(os.sleep, 0.1)

os.reboot()

-- os.reboot() never returns; if it ever does, treat as failure
return 0
