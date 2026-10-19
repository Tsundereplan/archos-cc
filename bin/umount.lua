-- bin/umount.lua  —  Unmount a filesystem
-- Usage:
--   umount <mountpoint>      unmount the filesystem at <mountpoint>
--   umount --help            show this help

local FS = _G.FS
local args = {...}
if not args or #args == 0 then args = arg or {} end

-- -- Help --------------------------------------------------------------------
if args[1] == "--help" or args[1] == "-h" then
    io.write("Usage: umount <mountpoint>\n")
    io.write("Unmount a previously-mounted filesystem.\n")
    return 0
end

if #args == 0 then
    io.stderr:write("umount: no mountpoint specified\n")
    return 1
end

if not FS or not FS.umount then
    io.stderr:write("umount: virtual filesystem not available\n")
    return 1
end

local mountpoint = args[1]
local ok, err = FS.umount(mountpoint)
if not ok then
    io.stderr:write("umount: " .. tostring(mountpoint) .. ": " ..
                    tostring(err or "not mounted") .. "\n")
    return 1
end
return 0
