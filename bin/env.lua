-- bin/env.lua  —  Display or modify the environment, then run a command
-- Usage:
--   env                     print all environment variables as KEY=VALUE
--   env VAR=value ... CMD   set VAR(s) and exec CMD with the rest of the args

local Kernel = _G.Kernel
local Process = _G.Process
local args = arg or {...}

-- -- Parse leading VAR=value tokens -- --
local sets = {}
local rest = {}
local sawCommand = false
for _, a in ipairs(args) do
    if not sawCommand then
        local k, v = a:match("^([%w_]+)=(.*)$")
        if k then
            sets[k] = v
        else
            -- First non-VAR=value token starts the command
            sawCommand = true
            table.insert(rest, a)
        end
    else
        table.insert(rest, a)
    end
end

-- -- No command: dump environment -- --
if #rest == 0 then
    local proc = Process and Process.current()
    local env = proc and proc.env or {}
    -- Sort keys for stable output
    local keys = {}
    for k, _ in pairs(env) do table.insert(keys, k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
        print(k .. "=" .. tostring(env[k]))
    end
    return 0
end

-- -- Apply env vars to current process (so the child inherits them) -- --
if Kernel then
    for k, v in pairs(sets) do
        Kernel.setEnv(k, v)
    end
end

-- -- Locate and run the command -- --
local cmd = rest[1]
local cmdArgs = {}
for i = 2, #rest do table.insert(cmdArgs, rest[i]) end

-- Resolve the executable via PATH
local function findExecutable(name)
    if name:sub(1, 1) == "/" or name:sub(1, 2) == "./" or name:sub(1, 3) == "../" then
        if fs.exists(name) then return name end
        return nil
    end
    local pathStr = Kernel and Kernel.getEnv("PATH") or "/bin:/sbin:/usr/bin"
    for raw in tostring(pathStr):gmatch("[^:]+") do
        local dir = raw
        if dir == "." then dir = Kernel and Kernel.getCwd() or "/" end
        local candidate = dir .. "/" .. name
        if fs.exists(candidate) then return candidate end
        if name:sub(-4) ~= ".lua" then
            candidate = candidate .. ".lua"
            if fs.exists(candidate) then return candidate end
        end
    end
    return nil
end

local exePath = findExecutable(cmd)
if not exePath then
    io.stderr:write("env: '" .. cmd .. "': No such file or directory\n")
    return 127
end

-- Spawn child, wait for it, return its exit code
if Kernel and Kernel.exec then
    local pid = Kernel.exec(exePath, cmdArgs)
    if not pid then
        io.stderr:write("env: failed to execute: " .. exePath .. "\n")
        return 1
    end
    local code = Kernel.wait(pid)
    return code or 0
else
    -- Fallback: os.run in a fresh env
    local env = {}
    for k, v in pairs(sets) do env[k] = v end
    local ok = os.run(env, exePath, table.unpack(cmdArgs))
    return ok and 0 or 1
end
