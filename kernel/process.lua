--[[
    kernel/process.lua  —  Process manager for ArchOS-CC
    ===================================================
    Each process is a Lua coroutine running in a sandboxed
    environment. The kernel scheduler (scheduler.lua) round-robins
    between them, dispatching events.

    Process state machine:
        created -> ready -> running -> sleeping/Waiting -> ready -> ... -> dead

    Each process has:
      pid           - unique numeric id (1..N)
      ppid          - parent pid
      uid           - owner user id
      gid           - owner group id
      cwd           - current working directory
      env           - environment table (PATH, HOME, USER, ...)
      argv          - command line arguments
      coro          - the underlying coroutine
      status        - "ready", "running", "sleeping", "waiting", "dead"
      exitCode      - exit code (set on death)
      window        - term.redirect target (or nil for inherited)
      children      - list of pids spawned by this process
      signals       - queued signals (TERM, KILL, INT)
      name          - process name (for ps/top)
      startTime     - os.clock() at creation
      cpuTime       - accumulated os.clock() delta
]]

local Process = {}
Process.__index = Process

local Kernel = nil  -- forward reference; will be set by scheduler

-- PID counter
local nextPID = 1
-- Process table: pid -> process
local processes = {}
-- Process lookup by name
local processByName = {}

-- Signal codes
Process.SIGNALS = {
    TERM = 1,    -- request termination (can be caught)
    KILL  = 2,    -- forceful termination (cannot be caught)
    INT   = 3,    -- Ctrl+C equivalent
    HUP   = 4,    -- hangup (parent died)
    STOP  = 5,    -- pause (not yet implemented)
    CONT  = 6,    -- resume from stop (not yet implemented)
}

-- Generate next PID
local function genPID()
    local pid = nextPID
    nextPID = nextPID + 1
    return pid
end

-- Create a new process
function Process.spawn(fn, opts)
    opts = opts or {}
    if type(fn) ~= "function" then
        return nil, "spawn: fn must be a function"
    end

    local proc = setmetatable({
        pid       = genPID(),
        ppid      = opts.ppid or 0,
        uid       = opts.uid or 0,
        gid       = opts.gid or 0,
        user      = opts.user or "root",
        cwd       = opts.cwd or "/",
        env       = opts.env or {},
        argv      = opts.argv or {},
        name      = opts.name or "unknown",
        status    = "ready",
        exitCode  = nil,
        coro      = nil,
        window    = opts.window,
        children  = {},
        signals   = {},
        startTime = os.clock(),
        cpuTime   = 0,
        waitFor   = nil,  -- list of event filters (or nil for any)
        sleepUntil = nil, -- os.clock() time to wake up
        stdout    = nil,  -- optional redirect
        stderr    = nil,
    }, Process)

    -- Inherit environment from parent if not specified
    if opts.ppid and processes[opts.ppid] then
        local parent = processes[opts.ppid]
        if not opts.cwd then proc.cwd = parent.cwd end
        -- shallow-copy parent env
        for k, v in pairs(parent.env) do
            if proc.env[k] == nil then proc.env[k] = v end
        end
        -- Add to parent's children list
        table.insert(parent.children, proc.pid)
    end

    -- Default environment
    if not proc.env.PATH then
        proc.env.PATH = "/bin:/sbin:/usr/bin:."
    end
    if not proc.env.HOME then
        proc.env.HOME = "/root"
    end
    if not proc.env.USER then
        proc.env.USER = proc.user
    end
    if not proc.env.SHELL then
        proc.env.SHELL = "/bin/sh.lua"
    end
    if not proc.env.PS1 then
        proc.env.PS1 = "[\\u@\\h \\W]\\$ "
    end

    -- Build the coroutine. Wrap fn so it can yield events.
    proc.coro = coroutine.create(function(...)
        -- Run user code; trap errors
        local ok, err = pcall(fn, ...)
        if not ok then
            proc.exitCode = 1
            proc.errorMsg = tostring(err)
            -- Print to stderr if we have one
            if proc.stderr then
                local old = term.redirect(proc.stderr)
                print("[error] " .. tostring(err))
                if old then term.redirect(old) end
            end
        else
            proc.exitCode = 0
        end
        proc.status = "dead"
        -- Cleanup children (orphan them to init / pid 0)
        for _, cpid in ipairs(proc.children) do
            local child = processes[cpid]
            if child and child.status ~= "dead" then
                child.ppid = 1
                if processes[1] then
                    table.insert(processes[1].children, cpid)
                end
            end
        end
        return proc.exitCode
    end)

    processes[proc.pid] = proc
    if proc.name then
        processByName[proc.name] = processByName[proc.name] or {}
        table.insert(processByName[proc.name], proc.pid)
    end

    return proc
end

-- Get a process by pid
function Process.get(pid)
    return processes[pid]
end

-- Find processes by name
function Process.findByName(name)
    return processByName[name] or {}
end

-- List all processes (or only living ones)
function Process.list(aliveOnly)
    local out = {}
    for pid, proc in pairs(processes) do
        if not aliveOnly or proc.status ~= "dead" then
            table.insert(out, proc)
        end
    end
    table.sort(out, function(a, b) return a.pid < b.pid end)
    return out
end

-- Resume a process, dispatching an event
function Process.resume(proc, ...)
    if not proc or proc.status == "dead" then return false end

    -- Check if waiting on a filter that doesn't match
    -- (handled by scheduler)

    -- Apply pending signals first
    if #proc.signals > 0 then
        local sig = table.remove(proc.signals, 1)
        if sig == Process.SIGNALS.KILL then
            proc.status = "dead"
            proc.exitCode = -9
            return false, "killed"
        elseif sig == Process.SIGNALS.TERM or sig == Process.SIGNALS.INT then
            -- Inject as terminate event
            -- The process can catch it via os.pullEvent("terminate")
            -- but if it doesn't, it dies.
        end
    end

    -- Set window redirect
    local oldRedirect = nil
    if proc.window then
        oldRedirect = term.redirect(proc.window)
    end

    proc.status = "running"
    local startTime = os.clock()
    local ok, yieldOrErr = coroutine.resume(proc.coro, ...)
    proc.cpuTime = proc.cpuTime + (os.clock() - startTime)

    if oldRedirect then
        term.redirect(oldRedirect)
    end

    if not ok then
        proc.status = "dead"
        proc.exitCode = 1
        proc.errorMsg = tostring(yieldOrErr)
        return false, yieldOrErr
    end

    if coroutine.status(proc.coro) == "dead" then
        proc.status = "dead"
        -- exitCode was set inside the coroutine wrapper
        return true, proc.exitCode
    end

    -- Process yielded.
    -- yieldOrErr is either:
    --   "event_filter" -> wait for that event type
    --   nil            -> wait for any event
    --   "sleep"        -> sleepUntil was set
    if type(yieldOrErr) == "string" then
        proc.waitFor = { yieldOrErr }
        proc.status = "waiting"
    elseif type(yieldOrErr) == "table" then
        proc.waitFor = yieldOrErr
        proc.status = "waiting"
    else
        proc.waitFor = nil
        proc.status = "ready"
    end

    return true
end

-- Send a signal to a process
function Process.signal(pid, sig)
    local proc = processes[pid]
    if not proc then return false, "no such process" end
    if proc.status == "dead" then return false, "process already dead" end
    if sig == Process.SIGNALS.KILL then
        proc.status = "dead"
        proc.exitCode = -9
        return true
    end
    table.insert(proc.signals, sig)
    return true
end

-- Kill a process (SIGKILL)
function Process.kill(pid)
    return Process.signal(pid, Process.SIGNALS.KILL)
end

-- Wait for a process to finish (returns exitCode)
-- Currently implemented as polling from scheduler.
function Process.wait(pid)
    local proc = processes[pid]
    if not proc then return -1 end
    while proc.status ~= "dead" do
        os.sleep(0)
    end
    return proc.exitCode or 0
end

-- Get current process (set by scheduler on each resume)
local currentPID = nil
function Process.current()
    return currentPID and processes[currentPID] or nil
end

function Process.setCurrent(pid)
    currentPID = pid
end

function Process.currentPID()
    return currentPID
end

-- Environment accessors (used by processes via syscall)
function Process.getEnv(key)
    local proc = Process.current()
    if proc then return proc.env[key] end
    return nil
end

function Process.setEnv(key, value)
    local proc = Process.current()
    if proc then proc.env[key] = value; return true end
    return false
end

function Process.getCwd()
    local proc = Process.current()
    return proc and proc.cwd or "/"
end

function Process.setCwd(path)
    local proc = Process.current()
    if proc then proc.cwd = path; return true end
    return false
end

-- Get a snapshot of process info (for ps/top)
function Process.info(pid)
    local proc = processes[pid]
    if not proc then return nil end
    return {
        pid       = proc.pid,
        ppid      = proc.ppid,
        user      = proc.user,
        name      = proc.name,
        status    = proc.status,
        cpuTime   = proc.cpuTime,
        startTime = proc.startTime,
        cwd       = proc.cwd,
        argv      = proc.argv,
        exitCode  = proc.exitCode,
    }
end

-- Reap dead processes older than N seconds to free memory
function Process.reap(maxAge)
    maxAge = maxAge or 60
    local now = os.clock()
    for pid, proc in pairs(processes) do
        if proc.status == "dead" and (now - proc.startTime) > maxAge then
            processes[pid] = nil
        end
    end
end

return Process
