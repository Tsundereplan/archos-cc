--[[
    usr/bin/top.lua  —  Process monitor (like Unix `top`)
    =====================================================
    Displays live process list with CPU usage and status.
    Updates every second. Press 'q' to quit.
]]

local function render()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()

    -- Header
    term.setCursorPos(1, 1)
    if term.isColor() then
        term.setTextColor(colors.lightBlue)
        term.setBackgroundColor(colors.blue)
    end
    local header = " ArchOS-CC Task Manager   Uptime: "
    local stats = _G.Scheduler and _G.Scheduler.stats() or { uptime = 0 }
    header = header .. string.format("%.0fs", stats.uptime or 0)
    header = header .. "   Processes: " .. tostring(stats.processCount or 0)
    header = header .. string.rep(" ", math.max(0, w - #header))
    term.write(header:sub(1, w))
    if term.isColor() then term.setBackgroundColor(colors.black) end

    -- Column header
    term.setCursorPos(1, 2)
    if term.isColor() then term.setTextColor(colors.yellow) end
    term.write(string.format("  %-5s %-5s %-10s %-10s %-8s %s",
        "PID", "PPID", "USER", "STATUS", "CPU%", "COMMAND"))
    if term.isColor() then term.setTextColor(colors.gray) end
    term.setCursorPos(1, 3)
    term.write(string.rep("-", w))

    -- Process list
    local procs = _G.Process and _G.Process.list(true) or {}
    table.sort(procs, function(a, b)
        return (a.cpuTime or 0) > (b.cpuTime or 0)
    end)

    local uptime = stats.uptime or 1
    for i, proc in ipairs(procs) do
        if i > h - 5 then break end
        term.setCursorPos(1, 3 + i)
        local cpu = (proc.cpuTime or 0) / uptime * 100
        if term.isColor() then
            if proc.status == "running" then term.setTextColor(colors.green)
            elseif proc.status == "waiting" then term.setTextColor(colors.cyan)
            elseif proc.status == "sleeping" then term.setTextColor(colors.yellow)
            elseif proc.status == "dead" then term.setTextColor(colors.gray)
            else term.setTextColor(colors.white) end
        end
        local cmdName = proc.name or "?"
        if proc.argv and #proc.argv > 0 then
            cmdName = cmdName .. " " .. table.concat(proc.argv, " ")
        end
        term.write(string.format("  %-5d %-5d %-10s %-10s %5.1f%%  %s",
            proc.pid, proc.ppid or 0, proc.user or "?",
            proc.status or "?", cpu, cmdName:sub(1, w - 50)))
    end
    if term.isColor() then term.setTextColor(colors.gray) end

    -- Footer
    term.setCursorPos(1, h - 1)
    term.write(string.rep("-", w))
    term.setCursorPos(1, h)
    if term.isColor() then term.setTextColor(colors.yellow) end
    term.write(" Press 'q' to quit, 'k' to kill a process, 'r' to refresh now")
    if term.isColor() then term.setTextColor(colors.white) end
end

local function main()
    local timer = os.startTimer(1)
    while true do
        render()
        local event = { os.pullEvent() }
        if event[1] == "timer" and event[2] == timer then
            timer = os.startTimer(1)
        elseif event[1] == "char" then
            local c = event[2]:lower()
            if c == "q" then break
            elseif c == "k" then
                term.setCursorPos(1, select(2, term.getSize()))
                term.write("Kill PID: ")
                local pid = tonumber(read())
                if pid and _G.Kernel then
                    _G.Kernel.kill(pid)
                end
            elseif c == "r" then
                -- just re-render
            end
        end
    end
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    return 0
end

return main()
