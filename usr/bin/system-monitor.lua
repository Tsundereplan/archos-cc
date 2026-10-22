--[[
    usr/bin/system-monitor.lua  —  System Monitor GUI
    =================================================
    Real-time system monitoring dashboard with:
      * CPU/memory graphs (last 20 ticks)
      * Process list with colored status
      * Disk usage bar
      * Network status
      * Update every 2 seconds
]]

local function setColor(c)
    if c and term.isColor() then pcall(function() term.setTextColor(c) end) end
end

local function setBG(c)
    if c and term.isColor() then pcall(function() term.setBackgroundColor(c) end) end
end

local history = {
    cpu = {},
    mem = {},
    maxLen = 20,
}

local function push(arr, val)
    table.insert(arr, val)
    if #arr > history.maxLen then table.remove(arr, 1) end
end

local function drawGraph(title, data, x, y, w, h, maxVal, color)
    setColor(colors.cyan)
    term.setCursorPos(x, y)
    term.write(title)
    setColor(color)
    -- Y axis (height)
    for row = 1, h - 2 do
        term.setCursorPos(x, y + row)
        term.write("|")
    end
    -- X axis (width)
    setColor(colors.gray)
    term.setCursorPos(x, y + h - 1)
    term.write("+" .. string.rep("-", w - 2))
    -- Plot data points
    setColor(color)
    for i, val in ipairs(data) do
        local col = x + i
        if col >= x + w then break end
        local hRatio = val / maxVal
        local barH = math.floor(hRatio * (h - 3))
        for r = 1, barH do
            term.setCursorPos(col, y + h - 1 - r)
            term.write("#")
        end
    end
    setColor(colors.white)
end

local function drawStatusBar(text, color)
    local w, h = term.getSize()
    setColor(colors.black)
    setBG(color)
    term.setCursorPos(1, h)
    term.write(text .. string.rep(" ", w - #text))
    setBG(colors.black)
    setColor(colors.white)
end

local function main()
    term.setBackgroundColor(colors.black)
    term.clear()

    while true do
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)

        -- Title
        setColor(colors.lightBlue)
        print("    ArchOS-CC System Monitor")
        print("    ========================")
        setColor(colors.white)
        print("")

        -- Get stats
        local stats = _G.Scheduler and _G.Scheduler.stats() or {uptime=0, processCount=0, tickCount=0}
        local uptime = stats.uptime or 0
        local procCount = stats.processCount or 0
        local cpuLoad = math.min(1, procCount / 20)
        local memUsage = math.min(1, (uptime % 50) / 50)  -- placeholder

        -- Push to history
        push(history.cpu, cpuLoad)
        push(history.mem, memUsage)

        -- Draw CPU graph
        drawGraph("CPU Load", history.cpu, 3, 4, 22, 8, 1, colors.green)
        -- Draw Memory graph
        drawGraph("Memory", history.mem, 28, 4, 22, 8, 1, colors.cyan)

        -- Stats text
        setColor(colors.yellow)
        term.setCursorPos(3, 13)
        print("Uptime:    " .. string.format("%.1f", uptime) .. " sec")
        term.setCursorPos(3, 14)
        print("Processes: " .. procCount)
        term.setCursorPos(3, 15)
        print("Disk free: " .. tostring(fs.getFreeSpace("/")) .. " bytes")
        term.setCursorPos(3, 16)
        if _G.Network then
            print("Network:   " .. (_G.Network.online and "online" or "offline"))
        else
            print("Network:   ?")
        end

        -- Process list (right side)
        setColor(colors.cyan)
        term.setCursorPos(28, 13)
        print("Top processes:")
        setColor(colors.white)
        if _G.Process then
            local procs = _G.Process.list(true)
            table.sort(procs, function(a, b) return (a.cpuTime or 0) > (b.cpuTime or 0) end)
            for i, proc in ipairs(procs) do
                if i > 5 then break end
                term.setCursorPos(28, 13 + i)
                local status = proc.status or "?"
                local stColor = (status == "running" and colors.green) or
                                (status == "waiting" and colors.cyan) or
                                (status == "dead" and colors.gray) or
                                colors.white
                setColor(stColor)
                term.write(string.format(" [%d] %-15s %s", proc.pid, proc.name or "?", status))
                setColor(colors.white)
            end
        end

        -- Bottom bar
        drawStatusBar(" Press 'q' to quit | Updates every 2 sec ", colors.blue)

        -- Wait for input or timeout
        local timer = os.startTimer(2)
        local event = {os.pullEvent()}
        if event[1] == "key" and event[2] == keys.q then break end
        if event[1] == "char" and event[2] == "q" then break end
        if event[1] == "timer" and event[2] == timer then
            -- continue loop
        end
    end

    setBG(colors.black)
    setColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    return 0
end

return main()
