-- bin/uname.lua  —  Print system information
-- Usage:
--   uname              print kernel name (ArchOS-CC)
--   uname -s           kernel name
--   uname -n           network node hostname
--   uname -r           kernel release (version)
--   uname -m           machine hardware name
--   uname -p           processor type
--   uname -a           all of the above on one line

local args = {...}
if not args or #args == 0 then args = arg or {} end

local Kernel  = _G.Kernel
local Network = _G.Network
local BIOS    = _G.BIOS
local FS      = _G.FS

-- -- Collect flags -----------------------------------------------------------
local flags = { all = false, s = false, n = false, r = false, m = false, p = false }
local showHelp = false

for _, a in ipairs(args) do
    if a == "--help" or a == "-h" then
        showHelp = true
    elseif a == "-a" or a == "--all" then
        flags.all = true
    elseif a:sub(1, 1) == "-" and #a > 1 then
        -- combined short flags like -snrpm
        for j = 2, #a do
            local c = a:sub(j, j)
            if     c == "s" then flags.s = true
            elseif c == "n" then flags.n = true
            elseif c == "r" then flags.r = true
            elseif c == "m" then flags.m = true
            elseif c == "p" then flags.p = true
            elseif c == "a" then flags.all = true
            else
                io.stderr:write("uname: invalid option -- '" .. c .. "'\n")
                return 1
            end
        end
    end
end

if showHelp then
    io.write("Usage: uname [OPTION]...\n")
    io.write("Print system information.\n")
    io.write("  -a, --all    print all information\n")
    io.write("  -s           print the kernel name\n")
    io.write("  -n           print the network node hostname\n")
    io.write("  -r           print the kernel release\n")
    io.write("  -m           print the machine hardware name\n")
    io.write("  -p           print the processor type\n")
    return 0
end

-- -- Helpers -----------------------------------------------------------------

-- Read the VERSION field from /etc/os-release
local function getRelease()
    local content
    if FS and FS.exists and FS.open then
        if not FS.exists("/etc/os-release") then return "unknown" end
        local f = FS.open("/etc/os-release", "r")
        if not f then return "unknown" end
        content = f.readAll()
        f.close()
    else
        if not fs.exists("/etc/os-release") then return "unknown" end
        local f = fs.open("/etc/os-release", "r")
        if not f then return "unknown" end
        content = f.readAll()
        f.close()
    end
    if not content then return "unknown" end
    for line in content:gmatch("[^\r\n]+") do
        local v = line:match("^%s*VERSION=%s*\"?([^\"]*)\"?")
        if v and v ~= "" then return v end
    end
    return "unknown"
end

-- Hostname from _G.Network or BIOS hw label, falling back to "archos-cc"
local function getNode()
    if Network and Network.hostname then return Network.hostname end
    if BIOS and BIOS.hw and BIOS.hw.computerType then
        return tostring(BIOS.hw.computerType)
    end
    return "archos-cc"
end

-- Computer ID
local function getID()
    if BIOS and BIOS.hw and BIOS.hw.computerID ~= nil then
        return tostring(BIOS.hw.computerID)
    end
    return tostring(os.getComputerID and os.getComputerID() or 0)
end

-- Uptime from scheduler stats
local function getUptime()
    local sched = _G.Scheduler
    if sched and sched.stats then
        local ok, stats = pcall(sched.stats)
        if ok and stats and stats.uptime ~= nil then
            return tostring(stats.uptime)
        end
    end
    return "0"
end

-- -- Build the requested fields ----------------------------------------------
local kernelName = "ArchOS-CC"
local node       = getNode()
local release    = getRelease()
local machine    = "cc-tweaked"
local processor  = "lua"

if flags.all then
    -- "ArchOS-CC <hostname> <version> <computerID> <arch> <uptime>"
    io.write(string.format("%s %s %s %s %s %s\n",
        kernelName, node, release, getID(), machine, getUptime()))
    return 0
end

-- If no flags were set, default to -s (kernel name) like the real uname
local anyFlag = flags.s or flags.n or flags.r or flags.m or flags.p
if not anyFlag then
    io.write(kernelName .. "\n")
    return 0
end

local parts = {}
if flags.s then table.insert(parts, kernelName) end
if flags.n then table.insert(parts, node) end
if flags.r then table.insert(parts, release) end
if flags.m then table.insert(parts, machine) end
if flags.p then table.insert(parts, processor) end

io.write(table.concat(parts, " ") .. "\n")
return 0
