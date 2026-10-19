--[[
    de/tty.lua  —  TTY Desktop Environment (Arch Linux TTY style)
    ============================================================
    A minimal text-mode desktop environment that mimics the Arch Linux
    bare TTY. It is essentially a wrapper around /bin/login.lua that
    adds a small banner and resumes a login shell.

    This is the default DE for systems without color support or when
    a graphical DE is not desired.
]]

local function setColor(c)
    if term.isColor() then term.setTextColor(c) end
end

local function main()
    -- Clear screen
    term.clear()
    term.setCursorPos(1, 1)

    -- ASCII art header
    setColor(colors.lightBlue)
    print("")
    print("    ___                     ____   ____  _  __")
    print("   /   | ______ __ ___     /  _/  / __ \\/ |/ /")
    print("  / /| |/ __/ / // (_-<    / /   / /_/ /    / ")
    print(" /_/ |_|/_/  /_//_/___/   /___/  /____/_/|_/  ")
    setColor(colors.gray)
    print("")
    print("  Welcome to ArchOS-CC  -  TTY mode")
    print("  ===============================")
    print("")

    -- Show OS info from /etc/os-release
    if fs.exists("/etc/os-release") then
        local f = fs.open("/etc/os-release", "r")
        if f then
            for line in f.readLine do
                if line:match("^PRETTY_NAME=") then
                    local pn = line:gsub('^PRETTY_NAME="', ""):gsub('"$', "")
                    setColor(colors.white)
                    print("  " .. pn)
                end
            end
            f.close()
        end
    end
    setColor(colors.gray)
    print("  Kernel: ArchOS-CC 1.0.0 (Lua 5.1)")
    print("  Architecture: cc-tweaked")
    print("")

    -- Show /etc/issue if present (like getty does)
    if fs.exists("/etc/issue") then
        local f = fs.open("/etc/issue", "r")
        if f then
            for rawLine in f.readLine do
                local line = rawLine:gsub("\\n", "")
                line = line:gsub("\\s", "ArchOS-CC")
                line = line:gsub("\\h", _G.Network and _G.Network.hostname or "archos")
                line = line:gsub("\\r", tostring(os.getComputerID()))
                setColor(colors.cyan)
                print("  " .. line)
            end
            f.close()
        end
    end
    setColor(colors.white)
    print("")

    -- Hand off to /bin/login.lua (authenticates + spawns shell)
    local loginPath = "/bin/login.lua"
    if not fs.exists(loginPath) then
        setColor(colors.red)
        print("[tty] login program not found at " .. loginPath)
        print("[tty] Spawning shell directly as root ...")
        setColor(colors.white)
        loginPath = "/bin/sh.lua"
    end

    local Kernel = _G.Kernel
    if Kernel then
        local pid = Kernel.exec(loginPath, {})
        if pid then
            Kernel.wait(pid)
        end
    else
        -- Fallback: just run the file directly
        dofile(loginPath)
    end

    return 0
end

return main()
