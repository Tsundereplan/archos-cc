--[[
    kernel/syscall.lua  —  System call interface
    =============================================
    Exposes a Kernel.* API that processes can use to interact with the OS.
    These wrap Process/Scheduler/Permissions with safety checks.

    IMPORTANT: cached in _G._ARCHOS_SYSCALL so all callers share the
    same instance.

    Available syscalls:
      Kernel.spawn(fn, opts)       -> pid
      Kernel.kill(pid)             -> bool
      Kernel.signal(pid, sig)      -> bool
      Kernel.wait(pid)             -> exitCode
      Kernel.sleep(seconds)        -> nil
      Kernel.pullEvent(filter)     -> event
      Kernel.getEnv(key)           -> value
      Kernel.setEnv(key, value)
      Kernel.getCwd()              -> path
      Kernel.setCwd(path)
      Kernel.getuid()              -> uid
      Kernel.getuser()             -> username
      Kernel.exec(path, args, env) -> exitCode  (run a file as a child process)
      Kernel.pipe(readFn, writeFn)  -> sets up IPC pipe (advanced)
]]

-- Module cache
if _G._ARCHOS_SYSCALL then
    return _G._ARCHOS_SYSCALL
end

local Process  = dofile("/kernel/process.lua")
local Scheduler = dofile("/kernel/scheduler.lua")

local Kernel = {}

-- Spawn a child process
function Kernel.spawn(fn, opts)
    opts = opts or {}
    local proc = Process.current()
    if proc then
        opts.ppid = proc.pid
        opts.uid = opts.uid or proc.uid
        opts.gid = opts.gid or proc.gid
        opts.user = opts.user or proc.user
        opts.cwd = opts.cwd or proc.cwd
    end
    return Process.spawn(fn, opts)
end

-- Kill a process
function Kernel.kill(pid)
    return Process.kill(pid)
end

-- Send a signal
function Kernel.signal(pid, sig)
    return Process.signal(pid, sig)
end

-- Sleep
function Kernel.sleep(seconds)
    Scheduler.sleep(seconds)
end

-- Pull an event (with optional filter)
function Kernel.pullEvent(filter)
    return Scheduler.pullEvent(filter)
end

-- Pull with timeout
function Kernel.pullEventRaw(filter)
    return Scheduler.pullEvent(filter)
end

-- Wait for a child process to finish
function Kernel.wait(pid)
    return Process.wait(pid)
end

-- Environment accessors
function Kernel.getEnv(key)
    return Process.getEnv(key)
end

function Kernel.setEnv(key, value)
    return Process.setEnv(key, value)
end

function Kernel.getCwd()
    return Process.getCwd()
end

function Kernel.setCwd(path)
    return Process.setCwd(path)
end

function Kernel.getuid()
    local p = Process.current()
    return p and p.uid or 0
end

function Kernel.getgid()
    local p = Process.current()
    return p and p.gid or 0
end

function Kernel.getuser()
    local p = Process.current()
    return p and p.user or "root"
end

function Kernel.getpid()
    return Process.currentPID()
end

-- List processes (snapshot)
function Kernel.ps()
    return Process.list(true)
end

-- Execute a file as a child process
-- This is the heart of `sh.lua`'s exec()
function Kernel.exec(filePath, args, env)
    args = args or {}
    env = env or {}

    if not fs.exists(filePath) then
        return nil, "no such file: " .. filePath
    end

    -- Read the file
    local f = fs.open(filePath, "r")
    if not f then return nil, "cannot open: " .. filePath end
    local content = f.readAll()
    f.close()

    -- Compile with the current _G environment (sandboxed per-process would be better)
    local fn, err = load(content, filePath, "t", _G)
    if not fn then
        return nil, "compile error: " .. tostring(err)
    end

    local proc = Kernel.spawn(function()
        -- Set up argv
        local oldArg = arg
        arg = {[0] = filePath, table.unpack(args)}
        -- Run the file
        local ok, rerr = pcall(fn, table.unpack(args))
        arg = oldArg
        if not ok then
            io.stderr:write("[exec] " .. tostring(rerr) .. "\n")
            return 1
        end
        return 0
    end, {
        name = fs.getName(filePath),
        argv = args,
        env = env,
    })

    if not proc then return nil, "spawn failed" end
    return proc.pid
end

-- Run a file synchronously (block until done, return exit code)
function Kernel.execSync(filePath, args, env)
    local pid, err = Kernel.exec(filePath, args, env)
    if not pid then return nil, err end
    return Kernel.wait(pid)
end

-- Inject an event into the scheduler (for IPC)
function Kernel.sendEvent(event)
    Scheduler.injectEvent(event)
end

-- Re-export signals
Kernel.SIG = Process.SIGNALS

-- Cache the Syscall module.
_G._ARCHOS_SYSCALL = Kernel
return Kernel
