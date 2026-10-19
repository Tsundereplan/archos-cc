-- /sbin/mkfs.lua  —  Format a disk (just clears it)
-- Usage: mkfs.lua <side> [label]
local side = arg[1]
local label = arg[2] or "ArchOS-Disk"

if not side then
    print("Usage: mkfs <side> [label]")
    print("  side = disk drive side (left/right/top/bottom/front/back)")
    return 1
end

if not peripheral.isPresent(side) or peripheral.getType(side) ~= "drive" then
    print("mkfs: no disk drive at " .. side)
    return 1
end

local drive = peripheral.wrap(side)
if not drive.hasDisk() then
    print("mkfs: no disk in drive")
    return 1
end

-- Get the disk's mount path
local id = drive.getDiskID()
local mountPath
if id == nil then
    mountPath = "/disk_" .. side
else
    mountPath = id == 0 and "/disk" or "/disk" .. (id + 1)
end

if not fs.exists(mountPath) then
    fs.makeDir(mountPath)
end

-- Set the disk label
drive.setDiskLabel(label)
print("mkfs: formatted disk at " .. side)
print("       mount point: " .. mountPath)
print("       label: " .. label)

return 0
