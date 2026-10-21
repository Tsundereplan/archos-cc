--[[
    lib/fs.lua  —  Virtual filesystem layer
    =======================================
    Wraps the native CC:Tweaked `fs` API with:
      * Mount points (mapping paths to underlying disks/locations)
      * Permission checks via kernel/permissions.lua
      * Path normalization and resolution
      * Symlink emulation (config files in /etc/fstab)

    Mount table lives in /etc/fstab:
        /        <root>          rw
        /mnt/d0  disk_drive_0    rw
        /mnt/d1  disk_drive_1    rw

    On boot, /sbin/init.lua calls FS.mountAll() to mount all entries.
]]

local VFS = {}

-- Mount table: virtual_path -> {source=real_path, type=, options=, device=}
local mounts = {}

-- Root mount is always the CC root
mounts["/"] = {
    source = "/",
    type = "root",
    options = "rw",
}

-- Normalize a path: resolve . and .., remove duplicate slashes
function VFS.normalize(path)
    if not path or path == "" then return "/" end
    -- Make absolute relative to current process cwd
    if path:sub(1, 1) ~= "/" then
        local Kernel = _G.Kernel
        local cwd = Kernel and Kernel.getCwd and Kernel.getCwd() or "/"
        path = cwd .. "/" .. path
    end
    -- Split
    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == "." then -- skip
        elseif part == ".." then
            table.remove(parts)
        else
            table.insert(parts, part)
        end
    end
    return "/" .. table.concat(parts, "/")
end

-- Find the mount that owns a path. Returns (mountEntry, relativePath)
function VFS.findMount(path)
    path = VFS.normalize(path)
    local bestMount = mounts["/"]
    local bestLen = 1
    for mpath, m in pairs(mounts) do
        if mpath ~= "/" then
            if path:sub(1, #mpath) == mpath and #mpath > bestLen then
                bestMount = m
                bestLen = #mpath
            end
        end
    end
    -- Strip the mount prefix from path
    local relPath = path:sub(bestLen + 1)
    if relPath == "" then relPath = "/" end
    if relPath:sub(1, 1) ~= "/" then relPath = "/" .. relPath end
    return bestMount, relPath
end

-- Translate a virtual path to a real CC path
function VFS.resolve(path)
    path = VFS.normalize(path)
    local mount, rel = VFS.findMount(path)
    if mount.source == "/" then
        return rel
    end
    return mount.source .. rel
end

-- Wrap fs operations with permission checks

function VFS.exists(path)
    local real = VFS.resolve(path)
    return fs.exists(real)
end

function VFS.isDir(path)
    local real = VFS.resolve(path)
    return fs.isDir(real)
end

function VFS.isReadOnly(path)
    local real = VFS.resolve(path)
    return fs.isReadOnly(real)
end

function VFS.getSize(path)
    local real = VFS.resolve(path)
    return fs.getSize(real)
end

function VFS.getDir(path)
    local normalized = VFS.normalize(path)
    local dir = normalized:match("^(.*)/[^/]+$")
    return dir and (dir == "" and "/" or dir) or "/"
end

function VFS.getName(path)
    return fs.getName(VFS.normalize(path))
end

function VFS.combine(...)
    return fs.combine(...)
end

function VFS.list(path)
    local real = VFS.resolve(path)
    if not fs.exists(real) then return {} end
    return fs.list(real)
end

function VFS.open(path, mode)
    local real = VFS.resolve(path)
    -- Permission check
    if _G.Permissions then
        local Kernel = _G.Kernel
        local uid = Kernel and Kernel.getuid and Kernel.getuid() or 0
        local gid = 0 -- TODO: pull from current process
        local action = (mode == "r") and "r" or "w"
        if not _G.Permissions.check(real, uid, gid, action) then
            return nil, "permission denied: " .. path
        end
    end
    return fs.open(real, mode)
end

function VFS.makeDir(path)
    local real = VFS.resolve(path)
    return fs.makeDir(real)
end

function VFS.delete(path)
    local real = VFS.resolve(path)
    return fs.delete(real)
end

function VFS.move(src, dst)
    local realSrc = VFS.resolve(src)
    local realDst = VFS.resolve(dst)
    return fs.move(realSrc, realDst)
end

function VFS.copy(src, dst)
    local realSrc = VFS.resolve(src)
    local realDst = VFS.resolve(dst)
    return fs.copy(realSrc, realDst)
end

function VFS.find(pattern)
    -- pattern is glob like "*.lua"
    -- We operate on root mount only for now
    return fs.find(pattern)
end

function VFS.getFreeSpace(path)
    local real = VFS.resolve(path)
    return fs.getFreeSpace(real)
end

-- Mount operations
function VFS.mount(virtualPath, sourcePath, opts)
    virtualPath = VFS.normalize(virtualPath)
    opts = opts or "rw"
    mounts[virtualPath] = {
        source = sourcePath,
        type = "disk",
        options = opts,
    }
    -- Notify event listeners
    if _G.Events then
        _G.Events.dispatch(_G.Events.TYPES.FS_MOUNT, virtualPath, sourcePath)
    end
end

function VFS.umount(virtualPath)
    virtualPath = VFS.normalize(virtualPath)
    if virtualPath == "/" then
        return false, "cannot unmount root"
    end
    if not mounts[virtualPath] then
        return false, "not mounted"
    end
    mounts[virtualPath] = nil
    if _G.Events then
        _G.Events.dispatch(_G.Events.TYPES.FS_UMOUNT, virtualPath)
    end
    return true
end

function VFS.mounts()
    local out = {}
    for path, m in pairs(mounts) do
        table.insert(out, { path = path, source = m.source, type = m.type, options = m.options })
    end
    table.sort(out, function(a, b) return a.path < b.path end)
    return out
end

-- Read all lines of a file as a single string
function VFS.readFile(path)
    local f = VFS.open(path, "r")
    if not f then return nil end
    local content = f.readAll()
    f.close()
    return content
end

-- Write a string to a file (overwrites)
function VFS.writeFile(path, content)
    local f = VFS.open(path, "w")
    if not f then return false, "cannot open file for writing" end
    f.write(content)
    f.close()
    return true
end

-- Append a string to a file
function VFS.appendFile(path, content)
    local f = VFS.open(path, "a")
    if not f then return false end
    f.write(content)
    f.close()
    return true
end

-- Walk a directory tree recursively
-- callback(path, isDir) for each entry
function VFS.walk(rootPath, callback)
    rootPath = VFS.normalize(rootPath)
    if not VFS.exists(rootPath) then return end
    local function walk(path)
        if VFS.isDir(path) then
            callback(path, true)
            local items = VFS.list(path)
            for _, name in ipairs(items) do
                local child = path
                if child:sub(-1) ~= "/" then child = child .. "/" end
                child = child .. name
                walk(child)
            end
        else
            callback(path, false)
        end
    end
    walk(rootPath)
end

-- Tree view of a directory
function VFS.tree(rootPath, maxDepth)
    maxDepth = maxDepth or 3
    local lines = {}
    local function walk(path, depth, prefix)
        if depth > maxDepth then return end
        local items = VFS.list(path)
        table.sort(items)
        for i, name in ipairs(items) do
            local child = path .. (path:sub(-1) == "/" and "" or "/") .. name
            local last = (i == #items)
            local branch = last and "+-- " or "+-- "
            table.insert(lines, prefix .. branch .. name)
            if VFS.isDir(child) then
                local nextPrefix = prefix .. (last and "    " or "|   ")
                walk(child, depth + 1, nextPrefix)
            end
        end
    end
    table.insert(lines, rootPath)
    walk(rootPath, 1, "")
    return lines
end

return VFS
