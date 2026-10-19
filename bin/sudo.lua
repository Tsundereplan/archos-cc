-- bin/sudo.lua  —  Execute a command as root (or another user)
-- Usage: sudo [-u USER] COMMAND [ARGS...]
local Kernel = _G.Kernel
local Users = _G.Users
if not Users and fs.exists("/lib/users.lua") then
    Users = dofile("/lib/users.lua")
end

local args = {...}
local targetUser = "root"
local cmdArgs = {}
local i = 1
while i <= #args do
    local a = args[i]
    if a == "-u" or a == "--user" then
        targetUser = args[i+1]
        i = i + 2
    elseif a == "-l" or a == "--list" then
        -- List allowed commands (we just say "all")
        print("User " .. (Kernel and Kernel.getEnv("USER") or "user") .. " may run all commands")
        return 0
    elseif a:sub(1, 1) ~= "-" then
        -- Rest is the command
        for j = i, #args do table.insert(cmdArgs, args[j]) end
        break
    else
        i = i + 1
    end
end

if #cmdArgs == 0 then
    io.stderr:write("sudo: no command specified\n")
    return 1
end

-- Check if sudo is allowed
-- In our simple model: anyone in the "wheel" or "sudo" group can use sudo
-- Or if the user is root already
local currentUser = Kernel and Kernel.getEnv("USER") or "root"
if currentUser ~= "root" then
    local user = Users.getUser(currentUser)
    if not user then
        io.stderr:write("sudo: unknown user\n")
        return 1
    end
    -- Check if user is in wheel/sudo group
    local canSudo = false
    if Users.groups["wheel"] then
        for _, m in ipairs(Users.groups["wheel"].members or {}) do
            if m == currentUser then canSudo = true; break end
        end
    end
    if not canSudo and Users.groups["sudo"] then
        for _, m in ipairs(Users.groups["sudo"].members or {}) do
            if m == currentUser then canSudo = true; break end
        end
    end
    -- First user (uid 1000) is allowed by default
    if not canSudo and user.uid == 1000 then canSudo = true end

    if not canSudo then
        io.stderr:write("sudo: " .. currentUser .. " is not in the sudoers file. This incident will be reported.\n")
        return 1
    end

    -- Authenticate
    term.write("[sudo] password for " .. currentUser .. ": ")
    local pw = read("*")
    if not Users.checkPassword(currentUser, pw) then
        print("sudo: authentication failed")
        return 1
    end
end

-- Find the command in PATH
local cmd = cmdArgs[1]
local cmdPath = nil
local searchPath = Kernel.getEnv("PATH") or "/bin:/sbin:/usr/bin"
for rawDir in searchPath:gmatch("[^:]+") do
    local dir = rawDir
    if dir == "." then dir = Kernel.getCwd() end
    local candidate = dir .. "/" .. cmd
    if cmd:sub(-4) ~= ".lua" then candidate = candidate .. ".lua" end
    if fs.exists(candidate) then cmdPath = candidate break end
end

if not cmdPath then
    io.stderr:write("sudo: command not found: " .. cmd .. "\n")
    return 127
end

-- Run with elevated permissions (uid 0)
local user = Users.getUser(targetUser)
if not user then
    io.stderr:write("sudo: target user '" .. targetUser .. "' does not exist\n")
    return 1
end

-- Save current user info
local Process = _G.Process
local cur = Process.current()
local savedUid, savedUser, savedHome, savedCwd
if cur then
    savedUid = cur.uid
    savedUser = cur.user
    savedHome = Kernel.getEnv("HOME")
    savedCwd = Kernel.getCwd()
    cur.uid = user.uid
    cur.gid = user.gid
    cur.user = targetUser
    Kernel.setEnv("USER", targetUser)
    Kernel.setEnv("HOME", user.home or "/root")
end

-- Execute
local pid = Kernel.exec(cmdPath, {table.unpack(cmdArgs, 2)})
local exitCode = 0
if pid then
    exitCode = Kernel.wait(pid) or 0
else
    exitCode = 1
end

-- Restore
if cur then
    cur.uid = savedUid
    cur.user = savedUser
    Kernel.setEnv("USER", savedUser)
    Kernel.setEnv("HOME", savedHome)
    Kernel.setCwd(savedCwd)
end
return exitCode
