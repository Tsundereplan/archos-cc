-- bin/passwd.lua  —  Change user password
local Users = _G.Users
if not Users and fs.exists("/lib/users.lua") then
    Users = dofile("/lib/users.lua")
end

local args = {...}
local username = arg and arg[1] or (_G.Kernel and _G.Kernel.getEnv("USER"))

if not username then
    io.stderr:write("passwd: missing username\n")
    return 1
end

-- Permission check: only root can change another user's password
local Kernel = _G.Kernel
local currentUser = Kernel and Kernel.getEnv("USER") or "root"
if currentUser ~= "root" and currentUser ~= username then
    io.stderr:write("passwd: you may not change the password for " .. username .. "\n")
    return 1
end

-- Verify user exists
if not Users.getUser(username) then
    io.stderr:write("passwd: user '" .. username .. "' does not exist\n")
    return 1
end

-- If not root, prompt for current password
if currentUser ~= "root" then
    term.write("Current password: ")
    local curpw = read("*")
    if not Users.checkPassword(username, curpw) then
        print("passwd: authentication failed")
        return 1
    end
end

-- Prompt for new password
term.write("New password: ")
local pw1 = read("*")
term.write("Retype new password: ")
local pw2 = read("*")

if pw1 ~= pw2 then
    print("passwd: passwords do not match")
    return 1
end

if pw1 == "" then
    print("passwd: empty password not allowed")
    return 1
end

-- Hash and store
Users.shadow = Users.shadow or {}
Users.shadow[username] = Users.hashPassword(pw1)
Users.save()
print("passwd: password updated for " .. username)
return 0
