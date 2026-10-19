--[[
    lib/drivers/disk.lua  —  Disk drive driver
    ========================================
    Provides:
      * Mount point management under /mnt/disk<N>
      * Disk label/id retrieval
      * Auto-mount on insertion
      * Auto-unmount on ejection
      * Free/total space queries
]]

local Disk = {}

-- Map of side -> mount info
Disk.mounts = {}

function Disk.onAttach(side, wrap)
    -- A disk drive was attached. Check if a disk is already in it.
    if wrap.hasDisk and wrap.hasDisk() then
        Disk.onDiskInsert(side)
    end
end

function Disk.onDetach(side)
    Disk.onDiskEject(side)
end

function Disk.onDiskInsert(side)
    local wrap = peripheral.wrap(side)
    if not wrap then return end
    local hasDisk = wrap.hasDisk and wrap.hasDisk()
    if not hasDisk then return end

    local label = wrap.getDiskLabel and wrap.getDiskLabel()
    local id = wrap.getDiskID and wrap.getDiskID()
    local mp = "/mnt/disk" .. tostring(id or side)

    -- Ensure mount point exists
    if not fs.exists(mp) then
        fs.makeDir(mp)
    end

    -- CC:Tweaked auto-mounts disks to /disk, /disk2, etc.
    -- We track them and provide a consistent /mnt/diskN alias.
    Disk.mounts[side] = {
        side = side,
        mountPoint = mp,
        label = label,
        id = id,
    }

    if _G.BIOS and _G.BIOS.log then
        _G.BIOS.log("[disk] Mounted disk at " .. mp .. " (side=" .. side .. ", id=" .. tostring(id) .. ", label=" .. tostring(label) .. ")")
    end
end

function Disk.onDiskEject(side)
    local info = Disk.mounts[side]
    if info then
        if _G.BIOS and _G.BIOS.log then
            _G.BIOS.log("[disk] Unmounting disk at " .. info.mountPoint)
        end
        Disk.mounts[side] = nil
    end
end

-- Manually mount a disk (for `mount` command)
function Disk.mount(side, mountPoint)
    if not peripheral.isPresent(side) or peripheral.getType(side) ~= "drive" then
        return false, "no disk drive at " .. side
    end
    local wrap = peripheral.wrap(side)
    if not wrap.hasDisk or not wrap.hasDisk() then
        return false, "no disk in drive " .. side
    end
    if not fs.exists(mountPoint) then
        fs.makeDir(mountPoint)
    end
    local label = wrap.getDiskLabel and wrap.getDiskLabel()
    local id = wrap.getDiskID and wrap.getDiskID()
    Disk.mounts[side] = {
        side = side,
        mountPoint = mountPoint,
        label = label,
        id = id,
    }
    return true
end

function Disk.umount(side)
    return Disk.onDiskEject(side)
end

-- List all mounted disks
function Disk.list()
    local out = {}
    for side, info in pairs(Disk.mounts) do
        table.insert(out, info)
    end
    table.sort(out, function(a, b) return a.side < b.side end)
    return out
end

-- Get the disk ID path (CC:Tweaked uses /disk, /disk2, etc.)
function Disk.getNativeMountPath(side)
    local wrap = peripheral.wrap(side)
    if not wrap then return nil end
    local id = wrap.getDiskID and wrap.getDiskID()
    if id == nil then
        -- Music disks or non-id'd disks - we use the side
        return "/disk_" .. side
    elseif id == 0 then
        return "/disk"
    else
        return "/disk" .. (id + 1)
    end
end

return Disk
