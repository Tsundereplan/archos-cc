--[[
    lib/arch/systemd.lua  —  Service manager (systemd-like)
    ======================================================
    Manages long-running background services:
      * Service files live in /etc/systemd/system/*.service
      * Each service has: ExecStart, ExecStop, After, Wants, etc.
      * Services run as their own coroutine/process
      * Status tracked in memory and persisted to /run/systemd/

    Commands (via systemctl.lua):
      systemctl start <name>
      systemctl stop <name>
      systemctl restart <name>
      systemctl status <name>
      systemctl enable <name>      (auto-start on boot)
      systemctl disable <name>
      systemctl list-units
      systemctl daemon-reload
]]

local Systemd = {}

Systemd.services = {}  -- name -> { state, pid, config, startedAt }
Systemd.enabled = {}   -- names of services to start on boot
Systemd.SERVICE_DIR = "/etc/systemd/system"
Systemd.RUN_DIR = "/run/systemd"

function Systemd.init()
    if not fs.exists(Systemd.SERVICE_DIR) then
        fs.makeDir(Systemd.SERVICE_DIR)
    end
    if not fs.exists(Systemd.RUN_DIR) then
        fs.makeDir(Systemd.RUN_DIR)
    end
    -- Load enabled list
    if fs.exists(Systemd.RUN_DIR .. "/enabled") then
        local f = fs.open(Systemd.RUN_DIR .. "/enabled", "r")
        if f then
            for line in f.readLine do
                if line and line ~= "" then
                    Systemd.enabled[line] = true
                end
            end
            f.close()
        end
    end
    -- Auto-start enabled services
    for name, _ in pairs(Systemd.enabled) do
        pcall(Systemd.start, name)
    end
end

-- Parse a service file
function Systemd.parseService(name)
    local path = Systemd.SERVICE_DIR .. "/" .. name .. ".service"
    if not fs.exists(path) then return nil, "no such service" end
    local f = fs.open(path, "r")
    if not f then return nil, "cannot read service file" end
    local content = f.readAll()
    f.close()
    local config = {
        name = name,
        after = {},
        wants = {},
        execStart = nil,
        execStop = nil,
        type = "simple",
        user = "root",
        restart = "no",
    }
    local section = nil
    for line in content:gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line == "" or line:sub(1, 1) == "#" or line:sub(1, 1) == ";" then
            -- skip
        elseif line:sub(1, 1) == "[" and line:sub(-1) == "]" then
            section = line:sub(2, -2)
        else
            local key, val = line:match("^([^=]+)%s*=%s*(.*)$")
            if key and val then
                key = key:gsub("^%s+", ""):gsub("%s+$", "")
                val = val:gsub("^%s+", ""):gsub("%s+$", "")
                if section == "Unit" then
                    if key == "After" then config.after = split(val)
                    elseif key == "Wants" then config.wants = split(val)
                    elseif key == "Description" then config.description = val end
                elseif section == "Service" then
                    if key == "ExecStart" then config.execStart = val
                    elseif key == "ExecStop" then config.execStop = val
                    elseif key == "Type" then config.type = val
                    elseif key == "User" then config.user = val
                    elseif key == "Restart" then config.restart = val end
                elseif section == "Install" then
                    if key == "WantedBy" then config.wantedBy = val end
                end
            end
        end
    end
    return config
end

function split(s, sep)
    if not s or s == "" then return {} end
    sep = sep or " "
    local out = {}
    for part in s:gmatch("[^" .. sep .. "]+") do
        table.insert(out, part)
    end
    return out
end

-- Start a service
function Systemd.start(name)
    if Systemd.services[name] and Systemd.services[name].state == "active" then
        return false, "already running"
    end
    local config = Systemd.parseService(name)
    if not config then return false, "no such service" end

    -- Start dependencies first
    for _, dep in ipairs(config.after or {}) do
        if not (Systemd.services[dep] and Systemd.services[dep].state == "active") then
            pcall(Systemd.start, dep)
        end
    end

    if not config.execStart then
        return false, "no ExecStart defined"
    end

    -- Spawn as a process
    local Kernel = _G.Kernel
    if not Kernel then return false, "kernel not available" end

    local pid = Kernel.exec(config.execStart, {}, {
        USER = config.user or "root",
    })
    if not pid then return false, "exec failed" end

    Systemd.services[name] = {
        state = "active",
        pid = pid,
        config = config,
        startedAt = os.time(),
    }
    if _G.Events then
        _G.Events.dispatch(_G.Events.TYPES.SERVICE_START, name)
    end
    return true
end

function Systemd.stop(name)
    local svc = Systemd.services[name]
    if not svc or svc.state ~= "active" then
        return false, "not running"
    end
    -- Run ExecStop if defined
    if svc.config.execStop then
        pcall(_G.Kernel.exec, svc.config.execStop)
    end
    -- Kill the process
    if _G.Kernel then
        _G.Kernel.kill(svc.pid)
    end
    svc.state = "inactive"
    if _G.Events then
        _G.Events.dispatch(_G.Events.TYPES.SERVICE_STOP, name)
    end
    return true
end

function Systemd.restart(name)
    Systemd.stop(name)
    return Systemd.start(name)
end

function Systemd.status(name)
    local svc = Systemd.services[name]
    if not svc then
        return { state = "not-loaded" }
    end
    return {
        state = svc.state,
        pid = svc.pid,
        startedAt = svc.startedAt,
        config = svc.config,
    }
end

function Systemd.enable(name)
    Systemd.enabled[name] = true
    -- Persist
    local f = fs.open(Systemd.RUN_DIR .. "/enabled", "a")
    if f then
        f.write(name .. "\n")
        f.close()
    end
    return true
end

function Systemd.disable(name)
    Systemd.enabled[name] = nil
    -- Rewrite enabled file
    local f = fs.open(Systemd.RUN_DIR .. "/enabled", "w")
    if f then
        for n, _ in pairs(Systemd.enabled) do
            f.write(n .. "\n")
        end
        f.close()
    end
    return true
end

function Systemd.listUnits()
    local units = {}
    -- Add all service files
    if fs.exists(Systemd.SERVICE_DIR) then
        for _, name in ipairs(fs.list(Systemd.SERVICE_DIR)) do
            if name:sub(-8) == ".service" then
                local svcName = name:sub(1, -9)
                local status = Systemd.status(svcName)
                table.insert(units, { name = svcName, state = status.state })
            end
        end
    end
    table.sort(units, function(a, b) return a.name < b.name end)
    return units
end

function Systemd.daemonReload()
    -- Re-parse all service files
    Systemd.services = {}
    -- Re-enable enabled services (but don't auto-start)
    return true
end

return Systemd
