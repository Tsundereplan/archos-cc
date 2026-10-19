-- bin/userdel.lua  —  Delete a user
local Users = _G.Users
if not Users and fs.exists("/lib/users.lua") then
    Users = dofile("/lib/users.lua")
end

local args = {...}
local removeHome = false
local username = nil
for _, a in ipairs(args) do
    if a == "-r" or a == "--remove" then removeHome = true
    elseif a == "--help" then
        print("Usage: userdel [OPTION] USERNAME")
        print("  -r, --remove   remove home directory and mail spool")
        return 0
    elseif a:sub(1, 1) ~= "-" then
        username = a
    end
end

if not username then
    io.stderr:write("userdel: missing username\n")
    return 1
end

local Kernel = _G.Kernel
if Kernel and Kernel.getuid() ~= 0 then
    io.stderr:write("userdel: permission denied\n")
    return 1
end

local user = Users.getUser(username)
if not user then
    io.stderr:write("userdel: user '" .. username .. "' does not exist\n")
    return 1
end

local ok, err = Users.delUser(username)
if not ok then
    io.stderr:write("userdel: " .. err .. "\n")
    return 1
end

if removeHome and user.home and fs.exists(user.home) then
    fs.delete(user.home)
    print("userdel: removed home directory " .. user.home)
end
print("userdel: deleted user '" .. username .. "'")
return 0
