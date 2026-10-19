-- bin/useradd.lua  —  Create a new user
-- Usage: useradd [OPTIONS] USERNAME
-- Options:
--   -m, --create-home    create home directory
--   -d, --home DIR       set home directory
--   -s, --shell PATH     set login shell
--   -u, --uid N          set user ID
--   -g, --gid N          set primary group ID
--   -G, --groups GROUPS  set additional groups (comma-separated)
--   -p, --password PWD   set initial password

local Users = _G.Users
if not Users and fs.exists("/lib/users.lua") then
    Users = dofile("/lib/users.lua")
end

local args = {...}
local opts = { createHome = true, groups = {} }
local username = nil
local i = 1
while i <= #args do
    local a = args[i]
    if a == "-m" or a == "--create-home" then opts.createHome = true
    elseif a == "-d" or a == "--home" then opts.home = args[i+1]; i = i + 1
    elseif a == "-s" or a == "--shell" then opts.shell = args[i+1]; i = i + 1
    elseif a == "-u" or a == "--uid" then opts.uid = tonumber(args[i+1]); i = i + 1
    elseif a == "-g" or a == "--gid" then opts.gid = tonumber(args[i+1]); i = i + 1
    elseif a == "-G" or a == "--groups" then
        for g in args[i+1]:gmatch("[^,]+") do table.insert(opts.groups, g) end
        i = i + 1
    elseif a == "-p" or a == "--password" then opts.password = args[i+1]; i = i + 1
    elseif a == "--help" then
        print("Usage: useradd [OPTIONS] USERNAME")
        print("Create a new user account.")
        return 0
    elseif a:sub(1, 1) ~= "-" then
        username = a
    end
    i = i + 1
end

if not username then
    io.stderr:write("useradd: missing username\n")
    return 1
end

if not Users then
    io.stderr:write("useradd: users library not available\n")
    return 1
end

-- Permission check (only root can create users)
local Kernel = _G.Kernel
if Kernel and Kernel.getuid() ~= 0 then
    io.stderr:write("useradd: permission denied (only root can create users)\n")
    return 1
end

local user, err = Users.addUser(username, opts)
if not user then
    io.stderr:write("useradd: " .. err .. "\n")
    return 1
end

-- Add to additional groups
for _, gname in ipairs(opts.groups) do
    local g = Users.groups[gname]
    if g then
        table.insert(g.members, username)
    end
end
Users.save()

print("useradd: created user '" .. username .. "' (uid=" .. user.uid .. ")")
if opts.createHome and user.home then
    print("         home: " .. user.home)
end
return 0
