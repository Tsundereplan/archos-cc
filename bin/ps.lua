-- bin/ps.lua  —  Report a snapshot of current processes
-- Usage: ps [OPTIONS]
-- Options:
--   -a, --all     show all processes (including dead)
--   -u, --user    show user/owner column
--   --help        show help

local Process = _G.Process
local Scheduler = _G.Scheduler
local args = arg or {...}

-- -- Options -- --
local showAll = false
local showUserCol = false
for _, a in ipairs(args) do
    if a == "--help" or a == "-h" then
        print("Usage: ps [OPTION]")
        print("  -a, --all   show all processes (including dead)")
        print("  -u, --user  show owner column")
        return 0
    elseif a == "-a" or a == "--all" then showAll = true
    elseif a == "-u" or a == "--user" then showUserCol = true
    elseif a:sub(1, 1) == "-" and #a > 1 then
        for j = 2, #a do
            local c = a:sub(j, j)
            if c == "a" then showAll = true
            elseif c == "u" then showUserCol = true
            else
                io.stderr:write("ps: invalid option -- '" .. c .. "'\n")
                return 1
            end
        end
    end
end

if not Process then
    io.stderr:write("ps: process subsystem not available\n")
    return 1
end

-- -- Gather data -- --
local procs = Process.list(not showAll)
local stats = Scheduler and Scheduler.stats() or { uptime = 0 }
local uptime = stats.uptime or 0

-- -- Header -- --
local header
if showUserCol then
    header = string.format("%5s %5s %-10s %-10s %5s  %s",
        "PID", "PPID", "USER", "STATUS", "CPU%", "COMMAND")
else
    header = string.format("%5s %5s %-10s %5s  %s",
        "PID", "PPID", "STATUS", "CPU%", "COMMAND")
end
if term.isColor() then term.setTextColor(colors.lightGray) end
print(header)
if term.isColor() then term.setTextColor(colors.white) end

-- -- Rows -- --
for _, p in ipairs(procs) do
    local cpuPct = 0
    if uptime > 0 then
        cpuPct = (p.cpuTime or 0) / uptime * 100
    end
    -- Build a command string from argv
    local cmd
    if p.argv and #p.argv > 0 then
        cmd = (p.name or p.argv[1]) .. " " .. table.concat(p.argv, " ", 2)
    else
        cmd = p.name or "?"
    end
    -- Trim long commands
    if #cmd > 40 then cmd = cmd:sub(1, 37) .. "..." end

    local row
    if showUserCol then
        row = string.format("%5d %5d %-10s %-10s %4.1f%% %s",
            p.pid or 0, p.ppid or 0, p.user or "?",
            p.status or "?", cpuPct, cmd)
    else
        row = string.format("%5d %5d %-10s %4.1f%% %s",
            p.pid or 0, p.ppid or 0, p.status or "?", cpuPct, cmd)
    end

    -- Color hint by status
    if term.isColor() then
        if p.status == "running" then term.setTextColor(colors.green)
        elseif p.status == "waiting" or p.status == "sleeping" then term.setTextColor(colors.yellow)
        elseif p.status == "dead" then term.setTextColor(colors.red)
        else term.setTextColor(colors.white) end
    end
    print(row)
    if term.isColor() then term.setTextColor(colors.white) end
end

return 0
