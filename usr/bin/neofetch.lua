--[[
    usr/bin/neofetch.lua  —  System info display (ASCII art + stats)
    ===================================================================
    Like the real neofetch, but for CC:Tweaked. Shows an ASCII logo
    and key system information.
]]

local function setColor(c)
    if term.isColor() then term.setTextColor(c) end
end

local function main()
    term.clear()
    term.setCursorPos(1, 1)

    local bios = _G.BIOS or {}
    local network = _G.Network or {}
    local scheduler = _G.Scheduler and _G.Scheduler.stats() or { uptime = 0 }
    local users = _G.Users

    -- Read OS info
    local osrelease = {}
    if fs.exists("/etc/os-release") then
        local f = fs.open("/etc/os-release", "r")
        if f then
            for line in f.readLine do
                local k, v = line:match("^([%w_]+)=(.*)$")
                if k and v then
                    v = v:gsub('^"', ""):gsub('"$', "")
                    osrelease[k] = v
                end
            end
            f.close()
        end
    end

    -- ASCII art logo
    setColor(colors.lightBlue)
    local logo = {
        "       ___                     ____   ____  _  __     ",
        "      /   | ______ __ ___     /  _/  / __ \\/ |/ /     ",
        "     / /| |/ __/ / // (_-<    / /   / /_/ /    /      ",
        "    /_/ |_|/_/  /_//_/___/   /___/  /____/_/|_/       ",
    }
    for _, line in ipairs(logo) do
        print(line)
    end
    print("")

    -- System info
    setColor(colors.cyan)
    local user = (_G.Kernel and _G.Kernel.getEnv("USER")) or "root"
    local hostname = network.hostname or (bios.hw and bios.hw.computerType) or "archos-cc"
    print(string.format(" %s@%s", user, hostname))
    setColor(colors.gray)
    print(" " .. string.rep("-", #(user .. "@" .. hostname)))
    print("")

    setColor(colors.yellow); term.write(" OS: ")
    setColor(colors.white)
    print(osrelease.NAME or "ArchOS-CC" .. " " .. (osrelease.VERSION or ""))

    setColor(colors.yellow); term.write(" Kernel: ")
    setColor(colors.white)
    print("ArchOS-CC kernel 1.0.0 (Lua)")

    setColor(colors.yellow); term.write(" Uptime: ")
    setColor(colors.white)
    print(string.format("%.0f seconds", scheduler.uptime or 0))

    setColor(colors.yellow); term.write(" Computer ID: ")
    setColor(colors.white)
    print(tostring(os.getComputerID()))

    setColor(colors.yellow); term.write(" Type: ")
    setColor(colors.white)
    local ctyp = "Advanced Computer"
    if turtle then ctyp = "Turtle" end
    if pocket then ctyp = "Pocket Computer" end
    if bios.hw and bios.hw.isTurtle then ctyp = "Turtle" end
    if bios.hw and bios.hw.isPocket then ctyp = "Pocket Computer" end
    print(ctyp)

    setColor(colors.yellow); term.write(" Label: ")
    setColor(colors.white)
    print(tostring(os.getComputerLabel() or "(none)"))

    setColor(colors.yellow); term.write(" Shell: ")
    setColor(colors.white)
    print(_G.Kernel and _G.Kernel.getEnv("SHELL") or "/bin/sh.lua")

    setColor(colors.yellow); term.write(" Terminal: ")
    setColor(colors.white)
    local tw, th = term.getSize()
    print(tostring(tw) .. "x" .. tostring(th) .. " " .. (term.isColor() and "(color)" or "(mono)"))

    setColor(colors.yellow); term.write(" Disk space: ")
    setColor(colors.white)
    local free = fs.getFreeSpace("/")
    print(tostring(free) .. " bytes free")

    -- Peripherals
    setColor(colors.yellow); term.write(" Peripherals: ")
    setColor(colors.white)
    local periphList = {}
    if bios.hw and bios.hw.peripherals then
        for side, ptype in pairs(bios.hw.peripherals) do
            table.insert(periphList, side .. "=" .. ptype)
        end
    end
    if #periphList == 0 then
        print("(none)")
    else
        print(table.concat(periphList, ", "))
    end

    -- Network status
    setColor(colors.yellow); term.write(" Network: ")
    setColor(colors.white)
    if network.online then
        print("online (channel " .. tostring(network.channel) .. ")")
    else
        setColor(colors.red); print("offline"); setColor(colors.white)
    end

    -- Memory usage (disk space)
    setColor(colors.yellow); term.write(" Memory: ")
    setColor(colors.white)
    local memUsed = 0
    -- Approximate by reading top-level dirs
    for _, d in ipairs({"/bin", "/sbin", "/usr", "/lib", "/kernel", "/etc"}) do
        if fs.exists(d) then
            local function walkSize(path)
                if fs.isDir(path) then
                    for _, name in ipairs(fs.list(path)) do
                        walkSize(path .. (path:sub(-1) == "/" and "" or "/") .. name)
                    end
                else
                    memUsed = memUsed + fs.getSize(path)
                end
            end
            pcall(walkSize, d)
        end
    end
    print(tostring(memUsed) .. " bytes used, " .. tostring(free) .. " bytes free")

    -- User count
    setColor(colors.yellow); term.write(" Users: ")
    setColor(colors.white)
    if users then
        local userList = users.listUsers()
        print(tostring(#userList) .. " total (" .. table.concat(userList, ", ") .. ")")
    else
        print("?")
    end

    -- Process count
    setColor(colors.yellow); term.write(" Processes: ")
    setColor(colors.white)
    if _G.Process then
        local procs = _G.Process.list(true)
        print(tostring(#procs))
    else
        print("?")
    end

    print("")
    setColor(colors.white)
    return 0
end

return main()
