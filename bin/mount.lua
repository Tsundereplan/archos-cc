-- bin/mount.lua  —  Mount a filesystem or list mounted filesystems
-- Usage:
--   mount                      list all mounts
--   mount <device> <mountpoint>            mount a device at mountpoint (rw)
--   mount -t <type> <device> <mountpoint>  mount with explicit filesystem type
--   mount --help              show this help

local FS = _G.FS
local args = {...}
if not args or #args == 0 then args = arg or {} end

-- -- Help --------------------------------------------------------------------
if args[1] == "--help" or args[1] == "-h" then
    io.write("Usage: mount [OPTION]... <device> <mountpoint>\n")
    io.write("Mount a filesystem, or list mounted filesystems.\n")
    io.write("\n")
    io.write("  -t, --type TYPE   filesystem type (default: rw/disk)\n")
    io.write("      --help        display this help and exit\n")
    return 0
end

-- -- Without a virtual FS layer we can do nothing -----------------------------
if not FS then
    io.stderr:write("mount: virtual filesystem not available\n")
    return 1
end

-- -- Parse arguments ---------------------------------------------------------
local opts = {}
local positional = {}
local i = 1
while i <= #args do
    local a = args[i]
    if a == "-t" or a == "--type" then
        opts.type = args[i + 1]
        if not opts.type then
            io.stderr:write("mount: option '" .. a .. "' requires an argument\n")
            return 1
        end
        i = i + 2
    elseif a == "--help" or a == "-h" then
        io.write("Usage: mount [OPTION]... <device> <mountpoint>\n")
        return 0
    elseif a:sub(1, 1) == "-" and #a > 1 then
        -- unknown long/short option
        io.stderr:write("mount: unknown option '" .. a .. "'\n")
        return 1
    else
        table.insert(positional, a)
        i = i + 1
    end
end

-- -- `mount` with no positional args: list mounts ----------------------------
if #positional == 0 then
    local mounts = FS.mounts and FS.mounts() or {}
    if #mounts == 0 then
        -- Root mount is always present per lib/fs.lua
        io.write("(no mounts)\n")
        return 0
    end
    for _, m in ipairs(mounts) do
        -- Format: DEVICE on MOUNTPOINT type TYPE (OPTIONS)
        local dev = m.source or m.device or "none"
        local path = m.path or m.mountpoint or "?"
        local tp = m.type or "unknown"
        local options = m.options or "rw"
        io.write(string.format("%s on %s type %s (%s)\n", dev, path, tp, options))
    end
    return 0
end

-- -- `mount <device> <mountpoint>`: mount a device ---------------------------
if #positional < 2 then
    io.stderr:write("mount: usage: mount [-t TYPE] <device> <mountpoint>\n")
    return 1
end

local device = positional[1]
local mountpoint = positional[2]

-- Device must exist (we check the underlying CC path via fs.exists)
if not fs.exists(device) then
    io.stderr:write("mount: " .. tostring(device) .. ": device not found\n")
    return 1
end

-- Mountpoint must exist (create if missing? POSIX mount requires it to exist)
if not FS.exists(mountpoint) then
    io.stderr:write("mount: mountpoint " .. tostring(mountpoint) ..
                    " does not exist\n")
    return 1
end

-- Build options string for the FS.mount() call.
-- FS.mount(virtualPath, sourcePath, opts)  where opts is "rw"/"ro"
local mountOpts = opts.type or "rw"

-- FS.mount() does not actually use the -t value as a real fs type today,
-- but we pass it through to the options for the listing to look right.
local optString = "rw"
if type(mountOpts) == "string" and (mountOpts == "ro" or mountOpts:find("ro")) then
    optString = "ro"
end

local ok, err
if FS.mount then
    ok, err = pcall(FS.mount, mountpoint, device, optString)
else
    io.stderr:write("mount: FS.mount() not available\n")
    return 1
end

if not ok then
    io.stderr:write("mount: " .. tostring(err or "unknown error") .. "\n")
    return 1
end
-- pcall returns (true, retval) on success; mount() returns nil currently.
return 0
