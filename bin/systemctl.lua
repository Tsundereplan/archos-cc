-- bin/systemctl.lua  —  Control the systemd-like service manager
-- Usage:
--   systemctl start <name>
--   systemctl stop <name>
--   systemctl restart <name>
--   systemctl status <name>
--   systemctl enable <name>
--   systemctl disable <name>
--   systemctl list-units [--all]
--   systemctl daemon-reload
--   systemctl reboot
--   systemctl poweroff

local Systemd = _G.Systemd
local Events  = _G.Events
local Kernel  = _G.Kernel
local args    = {...}

local hasColor = term.isColor and term.isColor()
local function c(col, fn)
    if hasColor then term.setTextColor(col) end
    fn()
    if hasColor then term.setTextColor(colors.white) end
end

local function usage()
    print("Usage: systemctl <command> [args...]")
    print("")
    print("Commands:")
    print("  start <name>          start a service")
    print("  stop <name>           stop a service")
    print("  restart <name>        restart a service")
    print("  status <name>         show service status")
    print("  enable <name>         enable a service to start on boot")
    print("  disable <name>        disable a service")
    print("  list-units [--all]    list known units")
    print("  daemon-reload         reload service files")
    print("  reboot                reboot the system")
    print("  poweroff              shut down the system")
    return 0
end

if not Systemd then
    io.stderr:write("systemctl: service manager not available\n")
    return 1
end

if #args == 0 or args[1] == "-h" or args[1] == "--help" then
    return usage()
end

local cmd = args[1]
local name = args[2]

-- Format a timestamp returned by os.time() into a readable string
local function formatTime(t)
    if not t then return "n/a" end
    return string.format("%.2f", t)
end

-- systemctl status <name>
local function doStatus(name)
    if not name then
        io.stderr:write("systemctl status: missing service name\n")
        return 1
    end
    local status = Systemd.status(name)
    if not status then
        c(colors.red, function() io.stderr:write("systemctl: no such unit '" .. name .. "'\n") end)
        return 1
    end

    local desc = (status.config and status.config.description) or name .. " service"
    local state = status.state or "unknown"
    local isOk = (state == "active" or state == "running")
    local marker = isOk and colors.green or colors.red
    local bullet = "*"

    c(marker, function() io.write(bullet .. " ") end)
    io.write(name .. ".service - ")
    c(colors.white, function() print(desc) end)

    print(string.format("     Loaded: loaded (/etc/systemd/system/%s.service)", name))
    if isOk then
        c(colors.green, function()
            print(string.format("     Active: active (running) since %s", formatTime(status.startedAt)))
        end)
    elseif state == "inactive" then
        c(colors.yellow, function()
            print("     Active: inactive (dead)")
        end)
    else
        c(colors.red, function()
            print(string.format("     Active: %s", state))
        end)
    end
    if status.pid then
        print(string.format("     Main PID: %d", status.pid))
    end
    if status.config then
        if status.config.execStart then
            c(colors.gray, function()
                print(string.format("     ExecStart: %s", status.config.execStart))
            end)
        end
        if status.config.user then
            c(colors.gray, function()
                print(string.format("     User: %s", status.config.user))
            end)
        end
    end
    return isOk and 0 or 3
end

-- systemctl list-units [--all]
if cmd == "list-units" then
    local showAll = (args[2] == "--all" or args[3] == "--all")
    local units = Systemd.listUnits and Systemd.listUnits() or {}
    if #units == 0 then
        c(colors.yellow, function() print("No units loaded.") end)
        return 0
    end
    print(string.format("  %-24s %-12s %s", "UNIT", "STATE", ""))
    print(string.rep("-", 50))
    for _, u in ipairs(units) do
        local st = u.state or "?"
        local col = (st == "active" or st == "running") and colors.green or colors.yellow
        c(col, function()
            print(string.format("  %-24s %-12s %s.service",
                u.name, st, u.name))
        end)
    end
    print("")
    print(string.format("  %d loaded units listed.", #units))
    if not showAll then
        c(colors.gray, function() print("  Pass --all to see everything.") end)
    end
    return 0
end

-- systemctl daemon-reload
if cmd == "daemon-reload" then
    Systemd.daemonReload()
    c(colors.green, function() print("daemon-reloaded") end)
    return 0
end

-- systemctl reboot
if cmd == "reboot" then
    if Events and Events.TYPES and Events.dispatch then
        Events.dispatch(Events.TYPES.REBOOT)
    end
    c(colors.yellow, function() print("Rebooting ...") end)
    os.sleep(0.5)
    if os.reboot then os.reboot() end
    return 0
end

-- systemctl poweroff
if cmd == "poweroff" then
    if Events and Events.TYPES and Events.dispatch then
        Events.dispatch(Events.TYPES.SHUTDOWN)
    end
    c(colors.yellow, function() print("Powering off ...") end)
    os.sleep(0.5)
    if os.shutdown then os.shutdown() end
    return 0
end

-- Commands that take a name
if not name then
    io.stderr:write("systemctl: '" .. cmd .. "' requires a service name\n")
    return 1
end

if cmd == "start" then
    local ok, err = Systemd.start(name)
    if ok then
        c(colors.green, function() print(string.format("Started %s.service", name)) end)
        return 0
    end
    c(colors.red, function() io.stderr:write("systemctl: " .. tostring(err or "failed") .. "\n") end)
    return 1

elseif cmd == "stop" then
    local ok, err = Systemd.stop(name)
    if ok then
        c(colors.green, function() print(string.format("Stopped %s.service", name)) end)
        return 0
    end
    c(colors.red, function() io.stderr:write("systemctl: " .. tostring(err or "failed") .. "\n") end)
    return 1

elseif cmd == "restart" then
    local ok, err = Systemd.restart(name)
    if ok then
        c(colors.green, function() print(string.format("Restarted %s.service", name)) end)
        return 0
    end
    c(colors.red, function() io.stderr:write("systemctl: " .. tostring(err or "failed") .. "\n") end)
    return 1

elseif cmd == "status" then
    return doStatus(name)

elseif cmd == "enable" then
    local ok, err = Systemd.enable(name)
    if ok then
        c(colors.green, function()
            print(string.format("Created symlink for %s.service (enabled)", name))
        end)
        return 0
    end
    c(colors.red, function() io.stderr:write("systemctl: " .. tostring(err or "failed") .. "\n") end)
    return 1

elseif cmd == "disable" then
    local ok, err = Systemd.disable(name)
    if ok then
        c(colors.green, function()
            print(string.format("Removed symlink for %s.service (disabled)", name))
        end)
        return 0
    end
    c(colors.red, function() io.stderr:write("systemctl: " .. tostring(err or "failed") .. "\n") end)
    return 1

else
    io.stderr:write("systemctl: unknown command '" .. cmd .. "'\n")
    usage()
    return 1
end
