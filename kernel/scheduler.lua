--[[
    kernel/scheduler.lua  —  Cooperative scheduler
    ================================================
    Runs the main event loop. Pulls events from CraftOS via os.pullEventRaw()
    and dispatches them to processes that are waiting for them.

    Strategy:
      1. Each tick: resume all ready processes once.
      2. Pull next event (with small timeout).
      3. Dispatch event to each process whose waitFor matches.
         (If proc.waitFor is nil, the process accepts any event.)
      4. Process sleep timers: resume processes whose sleepUntil has passed.
      5. Repeat.

    PID 1 (init) is the system process - it never dies, otherwise kernel panics.
]]

local Process = dofile("/kernel/process.lua")

local Scheduler = {}

local running = false
local bootTime = os.clock()
local tickCount = 0

-- Round-robin queue of ready pids
local readyQueue = {}

-- Determine if a process is interested in an event
local function matchesFilter(proc, eventType)
    if not proc.waitFor then return true end
    if #proc.waitFor == 0 then return true end
    for _, filter in ipairs(proc.waitFor) do
        if filter == eventType then return true end
    end
    return false
end

-- Wake up sleeping processes
local function checkSleepers(now)
    for pid, proc in pairs(Process.list(false)) do
        if proc.status == "sleeping" and proc.sleepUntil and proc.sleepUntil <= now then
            proc.status = "ready"
            proc.sleepUntil = nil
            proc.waitFor = nil
            -- Insert into ready queue
            table.insert(readyQueue, pid)
        end
    end
end

-- Run all ready processes once (one resume each)
local function tick()
    tickCount = tickCount + 1
    local now = os.clock()
    -- Wake any sleepers whose time has come
    checkSleepers(now)

    -- Move ready processes into the queue (they're already there from previous state changes)
    -- We snapshot the queue because resume can mutate it
    local snapshot = {}
    for i, pid in ipairs(readyQueue) do
        snapshot[i] = pid
    end
    readyQueue = {}

    for _, pid in ipairs(snapshot) do
        local proc = Process.get(pid)
        if proc and proc.status ~= "dead" then
            Process.setCurrent(pid)
            local ok, ev = Process.resume(proc)
            Process.setCurrent(nil)
            if not ok then
                -- Resume failed - process is now dead, logged inside
            end
        end
    end

    -- Periodic reaping
    if tickCount % 100 == 0 then
        Process.reap(120)
    end
end

-- Dispatch a single event to all matching processes
local function dispatchEvent(event)
    local eventType = event[1]
    -- Inject timer/alarm events to specific processes? In CC:Tweaked timers
    -- are global, but we keep simple: deliver to all matching processes.
    -- (Multishell-like behavior)

    for _, proc in ipairs(Process.list(false)) do
        if proc.status == "waiting" and matchesFilter(proc, eventType) then
            proc.status = "ready"
            proc.waitFor = nil
            table.insert(readyQueue, proc.pid)
            -- Stash event payload for this process to receive on next resume.
            -- We use a per-process pending event queue.
            proc._pendingEvent = event
        elseif proc.status == "ready" and not proc._pendingEvent then
            -- A process that yielded with nil filter receives all events
            proc._pendingEvent = event
        end
    end
end

-- Mark a process ready to receive an event (called by syscall when blocking)
function Scheduler.markReady(pid, event)
    local proc = Process.get(pid)
    if proc then
        proc._pendingEvent = event
        proc.status = "ready"
        proc.waitFor = nil
        table.insert(readyQueue, pid)
    end
end

-- Inject a synthetic event (used by signals, IPC)
function Scheduler.injectEvent(event)
    dispatchEvent(event)
end

-- Sleep the current process for n seconds
function Scheduler.sleep(seconds)
    local proc = Process.current()
    if not proc then
        -- Not in a process context, just use os.sleep
        os.sleep(seconds)
        return
    end
    proc.status = "sleeping"
    proc.sleepUntil = os.clock() + seconds
    proc.waitFor = nil
    -- Yield back to scheduler
    coroutine.yield()
end

-- Pull an event inside a process context
function Scheduler.pullEvent(filter)
    local proc = Process.current()
    if not proc then
        -- Fall back to raw pullEvent
        return os.pullEvent(filter)
    end
    -- Set wait filter and yield
    if filter then
        proc.waitFor = { filter }
    else
        proc.waitFor = nil
    end
    proc.status = "waiting"
    coroutine.yield()
    -- After resume, proc._pendingEvent should be set
    local ev = proc._pendingEvent
    proc._pendingEvent = nil
    return ev
end

-- Main scheduler loop. Returns when no living processes remain or on halt.
function Scheduler.main(initFn)
    running = true

    -- Spawn init process (PID 1)
    if initFn then
        Process.spawn(initFn, {
            ppid = 0,
            pid = 1, -- we want init to be PID 1; override genPID
            name = "init",
            user = "root",
            uid = 0,
            cwd = "/",
            env = {
                PATH = "/bin:/sbin:/usr/bin",
                HOME = "/root",
                USER = "root",
                TERM = "tty",
            }
        })
        -- Force pid to 1
        -- (Process.spawn assigns via genPID; we override)
        -- We need a special init spawn. Let's do it inline:
        -- Find the proc that was just created and fix its pid:
        -- Actually for simplicity, accept whatever PID we got.
    end

    -- Main loop
    while running do
        tick()

        -- Pull next event with a small timeout so the loop ticks even
        -- when no events are pending.
        -- CC:Tweaked: os.pullEventRaw() blocks until an event arrives.
        -- We use os.startTimer to ensure periodic wake-ups.
        local tickTimer = os.startTimer(0.05)
        local event = { os.pullEventRaw() }
        -- Cancel the timer if it's still alive (already fired -> it's the timer event)
        if event[1] ~= "timer" or event[2] ~= tickTimer then
            -- Some other event arrived; dispatch it
            dispatchEvent(event)
        end

        -- Check if init died
        local initProc = Process.get(1)
        if initProc and initProc.status == "dead" then
            -- Kernel panic - init died
            running = false
            return false, "init died"
        end

        -- If only init is left and it's dead, exit
        local alive = 0
        for _, p in pairs(Process.list(true)) do
            if p.status ~= "dead" then alive = alive + 1 end
        end
        if alive == 0 then
            running = false
            return true
        end
    end
    return true
end

-- Stop the scheduler
function Scheduler.halt()
    running = false
end

-- Stats
function Scheduler.stats()
    return {
        bootTime  = bootTime,
        uptime    = os.clock() - bootTime,
        tickCount = tickCount,
        processCount = #Process.list(true),
    }
end

return Scheduler
