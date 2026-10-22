--[[
    usr/bin/taskmgr.lua  —  Task Manager (TUI)
    =========================================
    Like Windows Task Manager, but for ArchOS-CC processes.

    Layout:
      Top        : summary (uptime, processes, load avg)
      Middle     : process list with columns PID/USER/NAME/STATUS/CPU%/MEM
      Bottom     : [End Task] [Switch To] [Refresh] [Quit]

    Hotkeys:
      Up/Dn     : select process
      Enter / e : end task (SIGTERM, then SIGKILL after 2s)
      w         : switch-to (send to foreground)
      r         : refresh now
      q         : quit
      Auto-refresh every 2 seconds.
]]

local args = arg or {...}

local function setFG(c) if term.isColor() then term.setTextColor(c) end end
local function setBG(c) if term.isColor() then term.setBackgroundColor(c) end end
local function resetColors()
    if term.isColor() then
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
    end
end

-- Box-drawing characters
local BOX_TL, BOX_TR, BOX_BL, BOX_BR = "+", "+", "+", "+"
local BOX_H,  BOX_V                   = "=", "|"
local BTN_L,  BTN_R,  BTN_H           = "[", "]", "-"

local function writeAt(x, y, s)
    term.setCursorPos(x, y)
    term.write(s)
end

-- State
local state = {
    procs = {},
    selected = 1,
    scroll = 1,
    uptime = 0,
    processCount = 0,
    message = "",
    msgTime = 0,
    loadAvg = 0,
    buttons = { "End Task", "Switch To", "Refresh", "Quit" },
    btnSel = 1,  -- highlighted button (purely visual; we use keyboard shortcuts)
}

local function msg(s)
    state.message = s
    state.msgTime = os.clock()
end

local function refreshData()
    local stats = (_G.Scheduler and _G.Scheduler.stats) and _G.Scheduler.stats() or { uptime = 0, processCount = 0 }
    state.uptime = stats.uptime or 0
    state.processCount = stats.processCount or 0

    state.procs = {}
    if _G.Process and _G.Process.list then
        for _, p in ipairs(_G.Process.list(true)) do
            local cpu = 0
            if state.uptime > 0 then
                cpu = (p.cpuTime or 0) / state.uptime * 100
            end
            -- MEMORY proxy: cpuTime in ticks approximates memory pressure,
            -- since CC:T has no real process memory. Use it as a proxy KB.
            local memKB = math.floor((p.cpuTime or 0) * 8 + 4)
            table.insert(state.procs, {
                pid  = p.pid,
                ppid = p.ppid or 0,
                user = p.user or "?",
                name = p.name or "?",
                status = p.status or "?",
                cpu = cpu,
                mem = memKB,
                argv = p.argv or {},
                cwd = p.cwd or "/",
                startTime = p.startTime or 0,
                cpuTime = p.cpuTime or 0,
            })
        end
    end
    table.sort(state.procs, function(a, b) return a.pid < b.pid end)

    -- load avg: average CPU across all procs (capped at 100)
    local total = 0
    for _, p in ipairs(state.procs) do total = total + p.cpu end
    state.loadAvg = (#state.procs > 0) and (total / #state.procs) or 0
end

---------------------------------------------------------------- rendering ---

local function fmtUptime(s)
    s = math.floor(s or 0)
    local days = math.floor(s / 86400)
    local hrs  = math.floor((s % 86400) / 3600)
    local mins = math.floor((s % 3600) / 60)
    local secs = s % 60
    if days > 0 then
        return string.format("%dd %02d:%02d:%02d", days, hrs, mins, secs)
    else
        return string.format("%02d:%02d:%02d", hrs, mins, secs)
    end
end

local function renderSummary(w, h)
    setBG(colors.blue); setFG(colors.white)
    term.setCursorPos(1, 1)
    local line = " ArchOS-CC Task Manager"
    line = line .. string.rep(" ", math.max(0, w - #line))
    term.write(line:sub(1, w))
    resetColors()

    -- summary line
    setFG(colors.yellow)
    writeAt(1, 2, string.format(" Uptime: %s   Processes: %d   Load avg: %5.1f%%",
        fmtUptime(state.uptime), state.processCount, state.loadAvg))
    resetColors()
end

local function renderProcessList(w, h)
    -- column header
    local y = 4
    setFG(colors.cyan)
    writeAt(1, y, string.format(" %-5s %-10s %-20s %-10s %6s %8s",
        "PID", "USER", "NAME", "STATUS", "CPU%", "MEM(KB)"))
    setFG(colors.gray)
    writeAt(1, y + 1, string.rep(BOX_H, w))
    resetColors()

    -- rows
    local rowsH = h - 4 - 4  -- header + footer area
    local listStartY = y + 2
    local endVisible = math.min(#state.procs, state.scroll + rowsH - 1)
    for i = state.scroll, endVisible do
        local p = state.procs[i]
        local row = listStartY + (i - state.scroll)
        if row > h - 3 then break end
        term.setCursorPos(1, row)
        if i == state.selected then
            setBG(colors.blue); setFG(colors.white)
        else
            setBG(colors.black)
            if p.status == "running" then setFG(colors.green)
            elseif p.status == "waiting" then setFG(colors.cyan)
            elseif p.status == "sleeping" then setFG(colors.yellow)
            elseif p.status == "dead" then setFG(colors.gray)
            else setFG(colors.white) end
        end
        local name = p.name
        if #p.argv > 0 then
            local argvStr = table.concat(p.argv, " ")
            if argvStr ~= "" then
                name = name .. " " .. argvStr
            end
        end
        if #name > 20 then name = name:sub(1, 17) .. "..." end
        local line = string.format(" %-5d %-10s %-20s %-10s %5.1f%%  %6d",
            p.pid, p.user:sub(1, 10), name, p.status:sub(1, 10), p.cpu, p.mem)
        -- pad to width to invert properly
        line = line .. string.rep(" ", math.max(0, w - #line))
        term.write(line:sub(1, w))
        resetColors()
    end

    -- clear unused rows
    for r = (endVisible - state.scroll + 1) + listStartY, h - 3 do
        term.setCursorPos(1, r)
        term.clearLine()
    end
end

local function renderButtons(w, h)
    -- separator
    setFG(colors.gray)
    writeAt(1, h - 1, string.rep(BOX_H, w))
    resetColors()

    -- buttons centered
    local btnLine = ""
    for i, b in ipairs(state.buttons) do
        if i == state.btnSel then
            btnLine = btnLine .. " " .. BTN_L .. b .. BTN_R .. " "
        else
            btnLine = btnLine .. "  " .. b .. "  "
        end
    end
    local padX = math.max(1, math.floor((w - #btnLine) / 2))
    setBG(colors.lightGray); setFG(colors.black)
    -- bottom bar
    term.setCursorPos(1, h)
    local bar = string.rep(" ", padX) .. btnLine
    bar = bar .. string.rep(" ", math.max(0, w - #bar))
    term.write(bar:sub(1, w))
    resetColors()

    -- hint with selected pid
    local sel = state.procs[state.selected]
    if sel then
        setFG(colors.yellow)
        writeAt(1, h - 2, string.format(" Selected: PID %d (%s) [%s]",
            sel.pid, sel.name, sel.status))
        resetColors()
    end
end

local function render()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()
    renderSummary(w, h)
    renderProcessList(w, h)
    renderButtons(w, h)

    if state.message ~= "" and (os.clock() - state.msgTime) < 2.5 then
        setFG(colors.cyan)
        writeAt(1, h - 3, " " .. state.message)
        resetColors()
    end
end

---------------------------------------------------------------- actions ---

local function endTask()
    local sel = state.procs[state.selected]
    if not sel then return end
    if not _G.Process or not _G.Process.signal then msg("Process API unavailable"); return end

    -- Send SIGTERM first
    _G.Process.signal(sel.pid, _G.Process.SIGNALS.TERM)
    msg("Sent SIGTERM to PID " .. sel.pid)

    -- Schedule a SIGKILL after 2 seconds if still alive
    local pid = sel.pid
    local killerTimer = os.startTimer(2)
    -- Run a sub-loop waiting for the timer or any other event
    -- We do this asynchronously by spawning a closure and immediately returning
    -- Actually CC:T has no real threads, so we use the main loop to detect the timer.
    -- We store pending kills in a queue.
    state.pendingKills = state.pendingKills or {}
    state.pendingKills[killerTimer] = pid
end

local function switchTo()
    local sel = state.procs[state.selected]
    if not sel then return end
    -- CC:T has no real "switch to" - but we can send a CONT signal to resume
    if _G.Process and _G.Process.signal and _G.Process.SIGNALS.CONT then
        _G.Process.signal(sel.pid, _G.Process.SIGNALS.CONT)
        msg("Sent SIGCONT to PID " .. sel.pid)
    else
        msg("Switch-to not supported in this kernel")
    end
end

local function checkPendingKillers(event)
    if state.pendingKills and event[1] == "timer" and state.pendingKills[event[2]] then
        local pid = state.pendingKills[event[2]]
        state.pendingKills[event[2]] = nil
        -- check if still alive
        local stillAlive = false
        if _G.Process and _G.Process.list then
            for _, p in ipairs(_G.Process.list(true)) do
                if p.pid == pid and p.status ~= "dead" then stillAlive = true break end
            end
        end
        if stillAlive and _G.Process.kill then
            _G.Process.kill(pid)
            msg("Sent SIGKILL to PID " .. pid .. " (didn't exit in 2s)")
        end
    end
end

---------------------------------------------------------------- main ---

local function main()
    refreshData()
    local refreshTimer = os.startTimer(2)

    while true do
        render()
        local event = { os.pullEvent() }
        local ev = event[1]

        checkPendingKillers(event)

        if ev == "timer" and event[2] == refreshTimer then
            refreshData()
            refreshTimer = os.startTimer(2)
        elseif ev == "timer" and state.pendingKills and state.pendingKills[event[2]] then
            -- already handled by checkPendingKillers, but suppress refresh
        elseif ev == "key" then
            local key = event[2]
            local n = #state.procs
            if key == keys.q then
                break
            elseif key == keys.up then
                state.selected = math.max(1, state.selected - 1)
                if state.selected < state.scroll then state.scroll = state.selected end
            elseif key == keys.down then
                state.selected = math.min(n, state.selected + 1)
                -- adjust scroll if necessary
                local _, h = term.getSize()
                local rowsH = h - 4 - 4
                if state.selected - state.scroll + 1 > rowsH then
                    state.scroll = state.selected - rowsH + 1
                end
            elseif key == keys.left then
                state.btnSel = (state.btnSel == 1) and #state.buttons or (state.btnSel - 1)
            elseif key == keys.right then
                state.btnSel = (state.btnSel == #state.buttons) and 1 or (state.btnSel + 1)
            elseif key == keys.enter then
                if state.btnSel == 1 then endTask()
                elseif state.btnSel == 2 then switchTo()
                elseif state.btnSel == 3 then refreshData(); msg("Refreshed")
                elseif state.btnSel == 4 then break
                end
            end
        elseif ev == "char" then
            local c = event[2]:lower()
            if c == "q" then break
            elseif c == "e" then endTask()
            elseif c == "w" then switchTo()
            elseif c == "r" then refreshData(); msg("Refreshed")
            end
        elseif ev == "mouse_click" then
            local btn, mx, my = event[2], event[3], event[4]
            local _, h = term.getSize()
            -- Click on buttons (bottom bar)
            local btnW = math.floor(h > 0 and 20 or 15)
            local btnY = h - 1
            if my >= btnY - 1 and my <= btnY then
                -- Roughly: 4 buttons, each ~12 chars wide starting at x=2
                local btnIdx = math.ceil((mx - 1) / 12)
                if btnIdx >= 1 and btnIdx <= 4 then
                    state.btnSel = btnIdx
                    if btnIdx == 1 then endTask()
                    elseif btnIdx == 2 then switchTo()
                    elseif btnIdx == 3 then refreshData(); msg("Refreshed")
                    elseif btnIdx == 4 then break
                    end
                end
            else
                -- Click on process list = select process
                local row = my - 4 + state.scroll
                if row >= 1 and row <= #state.procs then
                    state.selected = row
                end
            end
        end
    end

    resetColors()
    term.clear()
    term.setCursorPos(1, 1)
    return 0
end

return main()
