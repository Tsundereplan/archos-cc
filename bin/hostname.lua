-- bin/hostname.lua  —  Print or set the system hostname
-- Usage:
--   hostname                 print current hostname
--   hostname <newname>       set hostname (root only)
--   hostname --help          show this help

local Kernel  = _G.Kernel
local Network = _G.Network
local FS      = _G.FS
local args = {...}
if not args or #args == 0 then args = arg or {} end

-- -- Help --------------------------------------------------------------------
if args[1] == "--help" or args[1] == "-h" then
    io.write("Usage: hostname [NEWNAME]\n")
    io.write("Print or set the system hostname.\n")
    return 0
end

-- -- Print current hostname --------------------------------------------------
if #args == 0 then
    local name
    if Network and Network.hostname then name = Network.hostname end
    if (not name or name == "") and Kernel and Kernel.getEnv then
        name = Kernel.getEnv("HOSTNAME")
    end
    io.write((name or "archos-cc") .. "\n")
    return 0
end

-- -- Set new hostname --------------------------------------------------------
local newname = args[1]

-- Only root can change the hostname
if Kernel and Kernel.getuid and Kernel.getuid() ~= 0 then
    io.stderr:write("hostname: you must be root to change the hostname\n")
    return 1
end

-- Basic sanity check: hostnames are [a-zA-Z0-9._-]+, no spaces
if not newname:match("^[%w%._-]+$") then
    io.stderr:write("hostname: invalid name '" .. newname .. "'\n")
    return 1
end

-- Update the in-memory Network table
if not Network then
    io.stderr:write("hostname: network subsystem not available\n")
    return 1
end
Network.hostname = newname

-- Persist hostname to /etc/hostname (canonical location)
local function writeFile(path, content)
    if FS and FS.open then
        local f = FS.open(path, "w")
        if not f then return false end
        f.write(content)
        f.close()
        return true
    end
    if not fs.exists("/etc") then fs.makeDir("/etc") end
    local f = fs.open(path, "w")
    if not f then return false end
    f.write(content)
    f.close()
    return true
end
writeFile("/etc/hostname", newname .. "\n")

-- Keep the network config file in sync (lib/network.lua stores it there too)
if Network.saveConfig then
    pcall(Network.saveConfig)
end

-- Update the environment so child processes see the new name immediately
if Kernel and Kernel.setEnv then
    pcall(Kernel.setEnv, "HOSTNAME", newname)
end

io.write(newname .. "\n")
return 0
