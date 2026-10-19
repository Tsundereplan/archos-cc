-- /sbin/mkuser.lua  —  Create a new user (admin utility)
-- Usage: mkuser <username> [--uid N] [--password PWD] [--shell /bin/sh.lua] [--home /home/u]
local Users = _G.Users
if not Users and fs.exists("/lib/users.lua") then
    Users = dofile("/lib/users.lua")
end

if #arg < 1 then
    print("Usage: mkuser <username> [options]")
    print("  --uid N         Use specific UID")
    print("  --password P    Set password")
    print("  --shell PATH    Set login shell")
    print("  --home PATH     Set home directory")
    print("  --gecos STRING  Set GECOS field")
    return 1
end

local name = arg[1]
local opts = {}
local i = 2
while i <= #arg do
    if arg[i] == "--uid" then opts.uid = tonumber(arg[i+1]); i = i + 2
    elseif arg[i] == "--password" then opts.password = arg[i+1]; i = i + 2
    elseif arg[i] == "--shell" then opts.shell = arg[i+1]; i = i + 2
    elseif arg[i] == "--home" then opts.home = arg[i+1]; i = i + 2
    elseif arg[i] == "--gecos" then opts.gecos = arg[i+1]; i = i + 2
    else i = i + 1 end
end

local user, err = Users.addUser(name, opts)
if not user then
    print("mkuser: " .. err)
    return 1
end
print("mkuser: created user " .. name .. " (uid=" .. user.uid .. ")")
print("        home: " .. user.home)
print("        shell: " .. user.shell)
return 0
