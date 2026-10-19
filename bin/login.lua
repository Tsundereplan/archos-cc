--[[
    bin/login.lua  —  Login program
    ===============================
    Authenticates a user, then spawns their login shell.
    Replaces the previous getty concept (we don't have a separate getty).
]]

local Users = _G.Users
if not Users and fs.exists("/lib/users.lua") then
    Users = dofile("/lib/users.lua")
end

local function setColor(c)
    if term.isColor() then term.setTextColor(c) end
end

local function showIssue()
    -- Show /etc/issue if it exists
    if fs.exists("/etc/issue") then
        local f = fs.open("/etc/issue", "r")
        if f then
            local content = f.readAll()
            f.close()
            -- Substitute variables
            content = content:gsub("\\n", "\n")
            content = content:gsub("\\h", _G.Network and _G.Network.hostname or "archos")
            content = content:gsub("\\s", "ArchOS-CC")
            content = content:gsub("\\r", tostring(os.getComputerID()))
            print(content)
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

local function main()
    showIssue()

    -- If there's no root password set, auto-login as root for first boot
    local noPassword = false
    if Users and Users.shadow and not Users.shadow["root"] then
        setColor(colors.yellow)
        print("  [first boot] No root password set. Auto-login as root.")
        print("  Set a root password with: passwd")
        setColor(colors.white)
        noPassword = true
    end

    local username, password
    if noPassword then
        username, password = "root", ""
    else
        username, password = promptLogin()
        if not username then return 0 end
    end

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

    local user = Users and Users.getUser(username) or { username = username, uid = 0, gid = 0, home = "/root", shell = "/bin/sh.lua" }

    -- Set up environment
    if _G.Kernel then
        _G.Kernel.setEnv("USER", username)
        _G.Kernel.setEnv("HOME", user.home or "/root")
        _G.Kernel.setEnv("SHELL", user.shell or "/bin/sh.lua")
        _G.Kernel.setEnv("LOGNAME", username)
        _G.Kernel.setEnv("PATH", "/bin:/sbin:/usr/bin:/usr/local/bin:.")
        _G.Kernel.setEnv("PS1", username == "root" and "[\\u@\\h \\W]# " or "[\\u@\\h \\W]\\$ ")
        -- Update process user/uid
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
