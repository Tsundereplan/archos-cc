-- bin/kill.lua  —  Send a signal to a process
-- Usage: kill [OPTIONS] PID
-- Options:
--   -9            SIGKILL  (force; cannot be caught)
--   -15, -TERM    SIGTERM  (default; graceful request to terminate)
--   -HUP          SIGHUP   (hangup; parent died / reload)
--   -INT          SIGINT  (Ctrl+C equivalent)
--   -l            list signal names
--   --help        show help

local Process = _G.Process
local Kernel = _G.Kernel
local args = arg or {...}

-- -- Signal name -> code -- --
local SIGS = (Process and Process.SIGNALS) or {
    TERM = 1, KILL = 2, INT = 3, HUP = 4, STOP = 5, CONT = 6,
}
local NAMES = { "TERM", "KILL", "INT", "HUP", "STOP", "CONT" }

-- -- Options -- --
local sig = SIGS.TERM
local pids = {}

local i = 1
while i <= #args do
    local a = args[i]
    if a == "--help" or a == "-h" then
        print("Usage: kill [-SIGNAL] PID...")
        print("  -9, -KILL     force termination (cannot be caught)")
        print("  -15, -TERM    request termination (default)")
        print("  -HUP          hangup")
        print("  -INT          interrupt (Ctrl+C)")
        print("  -l            list signal names")
        return 0
    elseif a == "-l" or a == "--list" then
        for _, n in ipairs(NAMES) do
            print(string.format("%-6s %d", n, SIGS[n]))
        end
        return 0
    elseif a:sub(1, 1) == "-" and #a > 1 then
        local tail = a:sub(2)
        -- Numeric signal: -9, -15
        local num = tonumber(tail)
        if num then
            -- Map number -> code (1-based on our table values)
            -- Common conventions: 9 = KILL, 15 = TERM, 1 = HUP, 2 = INT
            if num == 9 then sig = SIGS.KILL
            elseif num == 15 then sig = SIGS.TERM
            elseif num == 1 then sig = SIGS.HUP
            elseif num == 2 then sig = SIGS.INT
            else
                io.stderr:write("kill: " .. num .. ": invalid signal specification\n")
                return 1
            end
        else
            local code = SIGS[tail:upper()]
            if not code then
                io.stderr:write("kill: " .. tail .. ": invalid signal\n")
                return 1
            end
            sig = code
        end
    else
        local n = tonumber(a)
        if not n then
            io.stderr:write("kill: " .. tostring(a) .. ": not a valid PID\n")
            return 1
        end
        table.insert(pids, n)
    end
    i = i + 1
end

if #pids == 0 then
    io.stderr:write("Usage: kill [-SIGNAL] PID...\n")
    return 1
end

if not Process and not Kernel then
    io.stderr:write("kill: process subsystem not available\n")
    return 1
end

-- -- Send signals -- --
local ret = 0
for _, pid in ipairs(pids) do
    local ok, err
    if sig == SIGS.KILL and Kernel and Kernel.kill then
        ok, err = Kernel.kill(pid)
    elseif Process and Process.signal then
        ok, err = Process.signal(pid, sig)
    elseif Kernel and Kernel.signal then
        ok, err = Kernel.signal(pid, sig)
    else
        ok = false
        err = "no signal facility"
    end
    if not ok then
        -- Match coreutils error wording
        if err and (err:find("no such process") or err:find("already dead")) then
            io.stderr:write("kill: (" .. pid .. ") - No such process\n")
        else
            io.stderr:write("kill: (" .. pid .. ") - " .. tostring(err or "unknown error") .. "\n")
        end
        ret = 1
    end
end

return ret
