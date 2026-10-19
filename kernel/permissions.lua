--[[
    kernel/permissions.lua  —  Permission / capability system
    =========================================================
    Tracks per-user permissions for:
      * Filesystem paths (read/write/execute per uid)
      * System calls (root-only: kill, mount, etc.)
      * Network access (which hosts/ports are allowed)
      * Peripheral access (which sides a user may touch)

    Permission model is similar to POSIX:
      * Files have an owner (uid) and group (gid).
      * Permission bits: read (4), write (2), execute (1).
      * Owner/Group/Other triples.
      * root (uid 0) bypasses all checks.

    Permission metadata is stored in:
      /var/db/permissions/  -- one file per path (slow lookup but simple)
        key: full path
        value: serialized "uid:gid:mode"

    For performance, common paths (/, /etc, /bin, /usr) are cached in memory.
]]

local Permissions = {}

-- In-memory cache: path -> {uid, gid, mode}
local cache = {}
local cacheLoaded = false
local DB_DIR = "/var/db/permissions"

-- Default permissions for system paths
local DEFAULTS = {
    ["/"]      = { uid = 0, gid = 0, mode = 755 },
    ["/bin"]   = { uid = 0, gid = 0, mode = 755 },
    ["/sbin"]  = { uid = 0, gid = 0, mode = 755 },
    ["/usr"]   = { uid = 0, gid = 0, mode = 755 },
    ["/lib"]   = { uid = 0, gid = 0, mode = 755 },
    ["/etc"]   = { uid = 0, gid = 0, mode = 755 },
    ["/var"]   = { uid = 0, gid = 0, mode = 755 },
    ["/home"]  = { uid = 0, gid = 0, mode = 755 },
    ["/root"]  = { uid = 0, gid = 0, mode = 700 },
    ["/tmp"]   = { uid = 0, gid = 0, mode = 1777 },
    ["/dev"]   = { uid = 0, gid = 0, mode = 755 },
    ["/mnt"]   = { uid = 0, gid = 0, mode = 755 },
    ["/proc"]  = { uid = 0, gid = 0, mode = 555 },
}

function Permissions.loadCache()
    if cacheLoaded then return end
    -- Start with defaults
    for path, info in pairs(DEFAULTS) do
        cache[path] = info
    end
    -- Load custom entries from disk if exists
    if fs.exists(DB_DIR) and fs.isDir(DB_DIR) then
        for _, name in ipairs(fs.list(DB_DIR)) do
            local path = "/" .. name:gsub("_", "/")
            local f = fs.open(DB_DIR .. "/" .. name, "r")
            if f then
                local content = f.readAll()
                f.close()
                local uid, gid, mode = content:match("^(%d+):(%d+):(%d+)$")
                if uid then
                    cache[path] = { uid = tonumber(uid), gid = tonumber(gid), mode = tonumber(mode) }
                end
            end
        end
    end
    cacheLoaded = true
end

-- Encode a path to a filename-safe string
local function encodePath(path)
    -- Replace / with _
    return path:gsub("/", "_"):gsub("^_", "")
end

function Permissions.saveEntry(path)
    local info = cache[path]
    if not info then return end
    if not fs.exists(DB_DIR) then fs.makeDir(DB_DIR) end
    local f = fs.open(DB_DIR .. "/" .. encodePath(path), "w")
    if not f then return end
    f.write(info.uid .. ":" .. info.gid .. ":" .. info.mode)
    f.close()
end

function Permissions.get(path)
    Permissions.loadCache()
    -- Try exact match
    if cache[path] then return cache[path] end
    -- Walk up: find longest matching prefix that has explicit perms
    local cur = path
    while cur ~= "" and cur ~= "/" do
        if cache[cur] then
            -- Inherit from parent for files
            return cache[cur]
        end
        local parent = cur:match("^(.*)/[^/]+$") or "/"
        if parent == "" then parent = "/" end
        cur = parent
    end
    return cache["/"]
end

function Permissions.set(path, uid, gid, mode)
    Permissions.loadCache()
    cache[path] = { uid = uid, gid = gid, mode = mode }
    Permissions.saveEntry(path)
end

-- Parse mode bits: returns owner_rwx, group_rwx, other_rwx
local function parseMode(mode)
    local other = mode % 10
    local group = math.floor(mode / 10) % 10
    local owner = math.floor(mode / 100) % 10
    return {
        owner = { r = (math.floor(owner / 4) % 2) == 1, w = (math.floor(owner / 2) % 2) == 1, x = (owner % 2) == 1 },
        group = { r = (math.floor(group / 4) % 2) == 1, w = (math.floor(group / 2) % 2) == 1, x = (group % 2) == 1 },
        other = { r = (math.floor(other / 4) % 2) == 1, w = (math.floor(other / 2) % 2) == 1, x = (other % 2) == 1 },
    }
end

-- Check if uid has access to path for given action
-- action: "r", "w", "x"
function Permissions.check(path, uid, gid, action)
    if uid == 0 then return true end  -- root bypass
    local info = Permissions.get(path)
    if not info then return false end
    local bits = parseMode(info.mode)
    if info.uid == uid then
        if action == "r" then return bits.owner.r
        elseif action == "w" then return bits.owner.w
        elseif action == "x" then return bits.owner.x end
    elseif info.gid == gid then
        if action == "r" then return bits.group.r
        elseif action == "w" then return bits.group.w
        elseif action == "x" then return bits.group.x end
    else
        if action == "r" then return bits.other.r
        elseif action == "w" then return bits.other.w
        elseif action == "x" then return bits.other.x end
    end
    return false
end

-- Convenience: get mode string like "rwxr-xr-x"
function Permissions.modeString(mode)
    local bits = parseMode(mode)
    local function triplet(t)
        return (t.r and "r" or "-") .. (t.w and "w" or "-") .. (t.x and "x" or "-")
    end
    return triplet(bits.owner) .. triplet(bits.group) .. triplet(bits.other)
end

-- Check root-only syscall permission
function Permissions.requireRoot(action)
    local Kernel = _G.Kernel
    if Kernel and Kernel.getuid then
        if Kernel.getuid() ~= 0 then
            error("Permission denied: " .. (action or "operation") .. " requires root")
        end
    end
end

-- sudo: temporarily escalate current process to root
function Permissions.sudo(callback)
    local Kernel = _G.Kernel
    if not Kernel then return callback() end
    local p = Kernel.current and Kernel.current()
    -- Kernel.current isn't defined here; use Process directly
    local Process = dofile("/kernel/process.lua")
    local cur = Process.current()
    if not cur then return callback() end
    local oldUid, oldGid = cur.uid, cur.gid
    cur.uid, cur.gid = 0, 0
    local ok, err = pcall(callback)
    cur.uid, cur.gid = oldUid, oldGid
    if not ok then error(err) end
    return err
end

return Permissions
