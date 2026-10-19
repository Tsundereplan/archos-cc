-- bin/chown.lua  —  Change file owner and group
-- Usage: chown USER[:GROUP] FILE...
local FS = _G.FS
local Users = _G.Users
local Permissions = _G.Permissions
local args = {...}

if #args < 2 then
    print("Usage: chown OWNER[:GROUP] FILE...")
    print("  Change the owner and/or group of each FILE to OWNER[:GROUP].")
    return 1
end

local spec = args[1]
local owner, group = spec:match("^([^:]+):?(.*)$")
local uid, gid
if Users then
    local u = Users.getUser(owner)
    if u then uid = u.uid end
    if group and group ~= "" then
        local g = Users.groups[group]
        if g then gid = g.gid end
    end
end
if not uid then
    io.stderr:write("chown: invalid user: '" .. owner .. "'\n")
    return 1
end
if group and group ~= "" and not gid then
    io.stderr:write("chown: invalid group: '" .. group .. "'\n")
    return 1
end

local ret = 0
for i = 2, #args do
    local path = args[i]
    if FS then path = FS.normalize(path) end
    if not fs.exists(path) then
        io.stderr:write("chown: cannot access '" .. args[i] .. "': No such file or directory\n")
        ret = 1
    else
        if Permissions then
            local info = Permissions.get(path) or { mode = 644 }
            local newGid = gid or info.gid
            Permissions.set(path, uid, newGid, info.mode)
        end
    end
end
return ret
