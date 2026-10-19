-- bin/ifconfig.lua  —  Display or configure network interfaces
-- Usage: ifconfig [up|down|hostname <name>]

local Network = _G.Network
local Kernel  = _G.Kernel
local args    = {...}

-- Color helpers
local hasColor = term.isColor and term.isColor()
local function c(col, fn)
    if hasColor then term.setTextColor(col) end
    fn()
    if hasColor then term.setTextColor(colors.white) end
end

-- Human-readable bytes
local function humanBytes(n)
    if not n or n < 1024 then return tostring(n or 0) end
    if n < 1024 * 1024 then return string.format("%.1fK", n / 1024) end
    return string.format("%.1fM", n / (1024 * 1024))
end

-- Show interface table
local function showInterfaces()
    if not Network then
        io.stderr:write("ifconfig: network subsystem unavailable\n")
        return 1
    end

    -- Header: hostname and status
    local hostname = Network.hostname or "archos-cc"
    local status   = Network.online and "online" or "offline"
    if hasColor then
        c(colors.cyan, function() io.write("hostname: ") end)
        c(Network.online and colors.green or colors.red, function() print(hostname .. "  (" .. status .. ")") end)
    else
        print("hostname: " .. hostname .. "  (" .. status .. ")")
    end
    print("")

    if not Network.modems or #Network.modems == 0 then
        c(colors.yellow, function() print("ifconfig: no network interfaces found") end)
        return 1
    end

    for i, m in ipairs(Network.modems) do
        local ifname = "eth" .. tostring(i - 1)
        local mtype  = m.isWireless and "wireless" or "wired"
        local flags  = Network.online and "<UP,BROADCAST,RUNNING>" or "<DOWN>"
        print(string.format("%s:  flags=4163%s  mtu 1500", ifname, flags))
        print(string.format("       type: %s", mtype))
        print(string.format("       side: %s", m.side or "?"))
        print(string.format("       inet %s  channel %d", hostname, Network.channel or 1))
        -- RX/TX stats are not tracked per-modem in this build; show zeros
        print(string.format("       RX packets:0  TX packets:0"))
        print(string.format("       collisions:0  txqueuelen:1000"))
        print(string.format("       RX bytes:0  TX bytes:0"))
        if i < #Network.modems then print("") end
    end
    return 0
end

-- Bring network up
local function ifUp()
    if not Network then
        io.stderr:write("ifconfig: network subsystem unavailable\n")
        return 1
    end
    if not Network.init then
        io.stderr:write("ifconfig: Network.init() not available\n")
        return 1
    end
    local ok, err = Network.init()
    if ok then
        c(colors.green, function() print("ifconfig: network up (" .. (Network.hostname or "?") .. ")") end)
        return 0
    end
    c(colors.red, function() io.stderr:write("ifconfig: failed to bring up network: " .. tostring(err) .. "\n") end)
    return 1
end

-- Bring network down
local function ifDown()
    if not Network then
        io.stderr:write("ifconfig: network subsystem unavailable\n")
        return 1
    end
    Network.online = false
    c(colors.yellow, function() print("ifconfig: network down") end)
    return 0
end

-- Set hostname (root only)
local function setHostname(newname)
    if not newname or newname == "" then
        io.stderr:write("ifconfig: missing hostname argument\n")
        return 1
    end
    -- Validate hostname (no spaces / weird chars)
    if not newname:match("^[%w%-%._]+$") then
        io.stderr:write("ifconfig: invalid hostname '" .. newname .. "'\n")
        return 1
    end
    -- Root only
    local uid = Kernel and Kernel.getuid and Kernel.getuid() or 0
    if uid ~= 0 then
        io.stderr:write("ifconfig: only root can set hostname\n")
        return 1
    end
    if not Network then
        io.stderr:write("ifconfig: network subsystem unavailable\n")
        return 1
    end
    Network.hostname = newname
    if Network.saveConfig then Network.saveConfig() end
    -- Persist to /etc/hostname as well
    if fs and not fs.exists("/etc") then fs.makeDir("/etc") end
    if fs then
        local f = fs.open("/etc/hostname", "w")
        if f then f.write(newname .. "\n"); f.close() end
    end
    c(colors.green, function() print("ifconfig: hostname set to '" .. newname .. "'") end)
    return 0
end

-- Usage
local function usage()
    print("Usage: ifconfig [OPTION]")
    print("Display or configure network interfaces.")
    print("")
    print("  ifconfig                  show interface table")
    print("  ifconfig up               bring the network up")
    print("  ifconfig down             take the network down")
    print("  ifconfig hostname <name>  set system hostname (root only)")
    return 0
end

-- Argument dispatch
local cmd = args[1]
if not cmd or cmd == "" then
    return showInterfaces()
elseif cmd == "up" then
    return ifUp()
elseif cmd == "down" then
    return ifDown()
elseif cmd == "hostname" then
    return setHostname(args[2])
elseif cmd == "-h" or cmd == "--help" then
    return usage()
else
    io.stderr:write("ifconfig: unknown command '" .. cmd .. "'\n")
    usage()
    return 1
end
