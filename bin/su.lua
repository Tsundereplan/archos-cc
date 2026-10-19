-- bin/su.lua  —  Switch user
-- Usage: su [USERNAME]
local Users = _G.Users
if not Users and fs.exists("/lib/users.lua") then
    Users = dofile("/lib/users.lua")
end

local args = {...}
local targetUser = args[1] or "root"
local command = nil

-- Parse args: su [-c "command"] [username]
local i = 1
while i <= #args do
    local a = args[i]
    if a == "-c" or a == "--command" then
        command = args[i+1]
        i = i + 2
    elseif a:sub(1, 1) ~= "-" then
        targetUser = a
        i = i + 1
    else
        i = i + 1
    end
end

local user = Users.getUser(targetUser)
if not user then
    io.stderr:write("su: user '" .. targetUser .. "' does not exist\n")
    return 1
end

-- If switching to root or another user, ask for their password (unless we're already root)
local Kernel = _G.Kernel
local currentUser = Kernel and Kernel.getEnv("USER") or "root"
if currentUser ~= "root" or targetUser ~= "root" then
    term.write("Password: ")
    local pw = read("*")
    if not Users.checkPassword(targetUser, pw) then
        print("su: authentication failed")
        return 1
    end
end

-- Update environment for the new user
if Kernel then
    Kernel.setEnv("USER", targetUser)
    Kernel.setEnv("HOME", user.home or "/root")
    Kernel.setEnv("SHELL", user.shell or "/bin/sh.lua")
    Kernel.setEnv("LOGNAME", targetUser)
    Kernel.setEnv("PS1", targetUser == "root" and "[\\u@\\h \\W]# " or "[\\u@\\h \\W]\\$ ")
    local Process = _G.Process
    if Process then
        local cur = Process.current()
        if cur then
            cur.uid = user.uid
            cur.gid = user.gid
            cur.user = targetUser
        end
    end
    if user.home and fs.exists(user.home) then
        Kernel.setCwd(user.home)
    end
end

if command then
    -- Run command and exit
    local path = _G.Kernel.getEnv("PATH") or "/bin"
    local cmd
    for dir in path:gmatch("[^:]+") do
        local candidate = dir .. "/" .. command:match("%S+")
        if fs.exists(candidate) then cmd = candidate break end
        candidate = candidate .. ".lua"
        if fs.exists(candidate) then cmd = candidate break end
    end
    if cmd then
        os.run({}, cmd)
    else
        -- Try shell built-in
        _G.Kernel.exec("/bin/sh.lua", {"-c", command})
    end
    return 0
end

-- Spawn a new shell as the target user
local shell = user.shell or "/bin/sh.lua"
if not fs.exists(shell) then shell = "/bin/sh.lua" end
local pid = Kernel.exec(shell, {})
if pid then
    return Kernel.wait(pid) or 0
end
return 1
