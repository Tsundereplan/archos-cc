--[[
    bin/login.lua  —  Login program (SECURE version)
    ===============================================
    Always requires username + password.
    If root has no password set, forces first-boot password setup
    before allowing login.
]]

local Users = _G.Users
if not Users and fs.exists("/lib/users.lua") then
    Users = dofile("/lib/users.lua")
end
-- Always load the user database
if Users then Users.load() end

local function setColor(c)
    if term.isColor() then term.setTextColor(c) end
end

local function showIssue()
    if fs.exists("/etc/issue") then
        local f = fs.open("/etc/issue", "r")
        if f then
            local content = f.readAll()
            f.close()
            content = content:gsub("\\n", "\n")
            content = content:gsub("\\h", _G.Network and _G.Network.hostname or "archos")
            content = content:gsub("\\s", "ArchOS-CC")
            content = content:gsub("\\r", tostring(os.getComputerID()))
            setColor(colors.lightBlue)
            print(content)
            setColor(colors.white)
        end
    else
        setColor(colors.lightBlue)
        print("    ArchOS-CC  " .. (os.date and os.date() or ""))
        setColor(colors.gray)
        print("    ============")
        print("")
    end
end

local function promptLogin()
    setColor(colors.white)
    term.write("login: ")
    setColor(colors.cyan)
    local username = read()
    if not username or username == "" then return nil end
    setColor(colors.white)
    term.write("Password: ")
    setColor(colors.cyan)
    local password = read("*")
    return username, password
end

-- Force user to set a password (used on first boot when root has no password)
local function forceSetPassword(username)
    setColor(colors.red)
    print("")
    print("  [SECURITY] No password is set for '" .. username .. "'!")
    print("  You MUST set a password before logging in.")
    setColor(colors.yellow)
    print("")
    while true do
        term.write("  New password: ")
        local pw1 = read("*")
        term.write("  Confirm:      ")
        local pw2 = read("*")
        if pw1 and pw1 ~= "" and pw1 == pw2 then
            -- Set the password
            if Users then
                Users.shadow = Users.shadow or {}
                Users.shadow[username] = Users.hashPassword(pw1)
                Users.save()
            end
            setColor(colors.green)
            print("  Password set. You can now log in.")
            setColor(colors.white)
            print("")
            return true
        else
            setColor(colors.red)
            print("  Passwords do not match or empty. Try again.")
            setColor(colors.white)
            print("")
        end
    end
end

local function main()
    showIssue()

    -- Check if root has a real password
    local rootNeedsPassword = false
    if Users and Users.shadow then
        local stored = Users.shadow["root"]
        if not stored or stored == "" then
            rootNeedsPassword = true
        end
    end

    -- If root has no password, force password setup BEFORE login
    if rootNeedsPassword then
        setColor(colors.yellow)
        print("  [first boot] Root account has no password.")
        setColor(colors.white)
        forceSetPassword("root")
    end

    -- Always prompt for login (never auto-login)
    local username, password = promptLogin()
    if not username then return 0 end

    -- Authenticate
    if Users then
        local ok, err = Users.authenticate(username, password)
        if not ok then
            setColor(colors.red)
            print("Login incorrect")
            setColor(colors.white)
            os.sleep(1)
            return 1
        end
    end

    local user = Users and Users.getUser(username) or
        { username = username, uid = 0, gid = 0, home = "/root", shell = "/bin/sh.lua" }

    -- Set up environment
    if _G.Kernel then
        _G.Kernel.setEnv("USER", username)
        _G.Kernel.setEnv("HOME", user.home or "/root")
        _G.Kernel.setEnv("SHELL", user.shell or "/bin/sh.lua")
        _G.Kernel.setEnv("LOGNAME", username)
        _G.Kernel.setEnv("PATH", "/bin:/sbin:/usr/bin:/usr/local/bin:.")
        _G.Kernel.setEnv("PS1", username == "root" and "[\\u@\\h \\W]# " or "[\\u@\\h \\W]\\$ ")
        local Process = _G.Process
        if Process then
            local cur = Process.current()
            if cur then
                cur.uid = user.uid
                cur.gid = user.gid
                cur.user = username
            end
        end
    end

    -- Change to home directory
    if _G.Kernel and user.home and fs.exists(user.home) then
        _G.Kernel.setCwd(user.home)
    end

    -- Dispatch login event
    if _G.Events then
        _G.Events.dispatch(_G.Events.TYPES.USER_LOGIN, username, user.uid)
    end

    setColor(colors.green)
    print("Welcome, " .. username .. "!")
    setColor(colors.gray)
    print("  Last login: " .. (os.date and os.date() or "unknown"))
    setColor(colors.white)
    print("")

    -- Spawn the user's shell
    local shell = user.shell or "/bin/sh.lua"
    if not fs.exists(shell) then
        shell = "/bin/sh.lua"
    end
    if not fs.exists(shell) then
        setColor(colors.red)
        print("login: no shell available")
        return 1
    end

    local Kernel = _G.Kernel
    local pid = Kernel.exec(shell, {})
    if pid then
        Kernel.wait(pid)
    end

    -- Logout
    setColor(colors.gray)
    print("logout")
    setColor(colors.white)
    if _G.Events then
        _G.Events.dispatch(_G.Events.TYPES.USER_LOGOUT, username)
    end
    return 0
end

return main()
