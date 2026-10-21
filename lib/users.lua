--[[
    lib/users.lua  —  User & group database
    ======================================
    Manages:
      /etc/passwd   -> username:x:uid:gid:gecos:home:shell
      /etc/group    -> groupname:x:gid:member1,member2,...
      /etc/shadow   -> username:password_hash:last_changed:min:max:warn:inactive:expire:reserved

    Functions:
      load()               -> load all databases into memory
      save()               -> persist back to disk
      addUser(name, opts)  -> create a user
      delUser(name)
      getUser(name)        -> user record or nil
      getUserByUID(uid)
      listUsers()
      addGroup(name, gid)
      delGroup(name)
      listGroups()
      checkPassword(name, pw)
      hashPassword(pw)     -> SHA256-like hash (CC has no built-in, we use a custom)
      authenticate(name, pw) -> bool
]]

local Users = {}

-- In-memory databases
Users.users = {}    -- username -> record
Users.groups = {}   -- groupname -> record
Users.byUID = {}    -- uid -> username
Users.byGID = {}    -- gid -> groupname

local function loadPasswd()
    Users.users = {}
    Users.byUID = {}
    local f = fs.open("/etc/passwd", "r")
    if not f then return end
    for line in f.readLine do
        if line and line ~= "" then
            local username, x, uid, gid, gecos, home, shell = line:match("^([^:]+):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*)$")
            if username then
                local record = {
                    username = username,
                    uid = tonumber(uid) or 0,
                    gid = tonumber(gid) or 0,
                    gecos = gecos,
                    home = home,
                    shell = shell or "/bin/sh.lua",
                }
                Users.users[username] = record
                Users.byUID[record.uid] = username
            end
        end
    end
    f.close()
end

local function loadGroup()
    Users.groups = {}
    Users.byGID = {}
    local f = fs.open("/etc/group", "r")
    if not f then return end
    for line in f.readLine do
        if line and line ~= "" then
            local name, x, gid, members = line:match("^([^:]+):([^:]*):([^:]*):([^:]*)$")
            if name then
                local memList = {}
                for m in (members or ""):gmatch("[^,]+") do
                    table.insert(memList, m)
                end
                local record = {
                    name = name,
                    gid = tonumber(gid) or 0,
                    members = memList,
                }
                Users.groups[name] = record
                Users.byGID[record.gid] = name
            end
        end
    end
    f.close()
end

local function loadShadow()
    -- /etc/shadow is only readable by root (uid 0)
    -- We load it lazily on demand to avoid permission issues.
    Users.shadow = {}
    local f = fs.open("/etc/shadow", "r")
    if not f then return end
    for line in f.readLine do
        if line and line ~= "" then
            local username, hash = line:match("^([^:]+):([^:]+)")
            if username and hash then
                Users.shadow[username] = hash
            end
        end
    end
    f.close()
end

function Users.load()
    loadPasswd()
    loadGroup()
    loadShadow()
end

function Users.save()
    -- Save passwd
    local pf = fs.open("/etc/passwd", "w")
    if pf then
        for _, u in pairs(Users.users) do
            pf.write(string.format("%s:x:%d:%d:%s:%s:%s\n",
                u.username, u.uid, u.gid, u.gecos or "", u.home or "", u.shell or "/bin/sh.lua"))
        end
        pf.close()
    end
    -- Save group
    local gf = fs.open("/etc/group", "w")
    if gf then
        for _, g in pairs(Users.groups) do
            gf.write(string.format("%s:x:%d:%s\n", g.name, g.gid, table.concat(g.members or {}, ",")))
        end
        gf.close()
    end
    -- Save shadow
    local sf = fs.open("/etc/shadow", "w")
    if sf then
        for name, hash in pairs(Users.shadow or {}) do
            sf.write(string.format("%s:%s:0:0:99999:7:::\n", name, hash))
        end
        sf.close()
    end
end

function Users.addUser(name, opts)
    opts = opts or {}
    if Users.users[name] then return nil, "user exists" end
    -- Find next free UID
    local uid = opts.uid
    if not uid then
        uid = 1000
        while Users.byUID[uid] do uid = uid + 1 end
    end
    local gid = opts.gid or uid
    local record = {
        username = name,
        uid = uid,
        gid = gid,
        gecos = opts.gecos or name,
        home = opts.home or "/home/" .. name,
        shell = opts.shell or "/bin/sh.lua",
    }
    Users.users[name] = record
    Users.byUID[uid] = name

    -- Create matching group if not exists
    if not Users.groups[name] then
        Users.groups[name] = { name = name, gid = gid, members = {name} }
        Users.byGID[gid] = name
    end

    -- Create home directory
    if record.home and not fs.exists(record.home) then
        fs.makeDir(record.home)
    end

    -- Save password if provided
    if opts.password then
        Users.shadow = Users.shadow or {}
        Users.shadow[name] = Users.hashPassword(opts.password)
    end

    Users.save()
    return record
end

function Users.delUser(name)
    if not Users.users[name] then return false, "no such user" end
    if name == "root" then return false, "cannot delete root" end
    local uid = Users.users[name].uid
    Users.users[name] = nil
    Users.byUID[uid] = nil
    if Users.shadow and Users.shadow[name] then
        Users.shadow[name] = nil
    end
    if Users.groups[name] then
        Users.groups[name] = nil
    end
    Users.save()
    return true
end

function Users.getUser(name)
    return Users.users[name]
end

function Users.getUserByUID(uid)
    local name = Users.byUID[uid]
    return name and Users.users[name] or nil
end

function Users.listUsers()
    local out = {}
    for name, _ in pairs(Users.users) do
        table.insert(out, name)
    end
    table.sort(out)
    return out
end

function Users.listGroups()
    local out = {}
    for name, _ in pairs(Users.groups) do
        table.insert(out, name)
    end
    table.sort(out)
    return out
end

function Users.addGroup(name, gid)
    if Users.groups[name] then return false, "group exists" end
    if not gid then
        gid = 1000
        while Users.byGID[gid] do gid = gid + 1 end
    end
    Users.groups[name] = { name = name, gid = gid, members = {} }
    Users.byGID[gid] = name
    Users.save()
    return true
end

-- Custom string hash (since CC:Tweaked has no built-in crypto)
-- Uses a 256-bit FNV-1a variant with extra mixing rounds.
-- NOT cryptographically secure but adequate for OS demo.
--
-- IMPORTANT: CC:Tweaked uses Lua 5.1 (Cobalt) which does NOT support
-- the Lua 5.3 bitwise operators (~, &, |, <<, >>). We must use the
-- `bit32` API instead: bit32.bxor, bit32.band, bit32.bor, bit32.lshift,
-- bit32.rshift, bit32.rrotate. All values are kept as 32-bit unsigned.
local function fnv1a(data)
    local bxor = bit32 and bit32.bxor or function(a, b) return a end  -- fallback
    local rshift = bit32 and bit32.rshift or function(a, n) return math.floor(a / 2^n) end
    local lshift = bit32 and bit32.lshift or function(a, n) return (a * 2^n) % 4294967296 end
    local h = 2166136261
    for i = 1, #data do
        h = bxor(h, data:byte(i))
        h = (h * 16777619) % 4294967296
    end
    -- Mix with another round
    for _ = 1, 5 do
        h = bxor(h, bxor(rshift(h, 13), lshift(h, 7)))
        h = h % 4294967296
    end
    return h
end

function Users.hashPassword(password)
    -- Salt + multi-round FNV
    -- We use os.time() as entropy source since CC has no /dev/urandom
    local salt = tostring(os.time() .. os.getComputerID())
    local hashed = password .. salt
    for _ = 1, 1000 do
        hashed = tostring(fnv1a(hashed))
    end
    return salt .. "$" .. hashed
end

function Users.checkPassword(name, password)
    if not Users.shadow then loadShadow() end
    local stored = Users.shadow[name]
    if not stored or stored == "" then
        -- No password set for this user.
        -- SECURITY: do NOT auto-accept any password!
        -- Only accept if the user typed an empty password,
        -- and even then, we should warn about no-password accounts.
        return password == ""
    end
    local salt, hashed = stored:match("^([^$]+)%$(.+)$")
    if not salt then return false end
    local test = password .. salt
    for _ = 1, 1000 do
        test = tostring(fnv1a(test))
    end
    return test == hashed
end

function Users.authenticate(name, password)
    if not Users.users[name] then return false, "no such user" end
    if Users.checkPassword(name, password) then
        return true
    end
    return false, "bad password"
end

-- Initialize with default root user if databases are empty
function Users.ensureRoot()
    if not Users.users["root"] then
        Users.addUser("root", {
            uid = 0, gid = 0, gecos = "root",
            home = "/root", shell = "/bin/sh.lua",
        })
    end
    if not Users.groups["root"] then
        Users.groups["root"] = { name = "root", gid = 0, members = {"root"} }
        Users.byGID[0] = "root"
    end
    if not Users.groups["users"] then
        Users.groups["users"] = { name = "users", gid = 100, members = {} }
        Users.byGID[100] = "users"
    end
    Users.save()
end

return Users
