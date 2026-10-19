--[[
    kernel/init.lua  —  ArchOS-CC kernel entry point
    =================================================
    Called by the bootloader. Sets up the system, then runs the init
    process (PID 1) which spawns the rest of the userland.

    Boot sequence:
      1. Load all kernel modules (process, scheduler, syscall, events, permissions)
      2. Load core libraries (fs, users, crypto, network)
      3. Initialize the PnP subsystem (drivers)
      4. Expose Kernel.* globally for use by userland
      5. Mount /proc, /dev (virtual FSes)
      6. Start systemd-like service manager (lib/arch/systemd.lua)
      7. Spawn PID 1 = init (/sbin/init.lua) which:
          - Reads /etc/passwd, /etc/fstab, /etc/network.conf
          - Mounts filesystems
          - Brings up network
          - Starts the login service
      8. Enter scheduler main loop

    This file is `dofile()`'d by the bootloader with a context table.
    It returns a function (the kernel main) that the bootloader runs.
]]

local Kernel = {}

-- Library loader: loads /lib/<name>.lua and caches it
local libCache = {}
local function require(name)
    if libCache[name] then return libCache[name] end
    local path = "/lib/" .. name .. ".lua"
    if not fs.exists(path) then
        return nil, "no such library: " .. name
    end
    local ok, lib = pcall(dofile, path)
    if not ok then return nil, lib end
    libCache[name] = lib
    return lib
end

function Kernel.main(ctx)
    local bootCtx = ctx or _G.BOOT_CONTEXT or {}
    local bios = _G.BIOS

    -- Reset screen
    term.clear()
    term.setCursorPos(1, 1)
    if term.isColor() then term.setTextColor(colors.lightBlue) end
    print("[kernel] ArchOS-CC kernel starting ...")
    print("")

    -- Load kernel modules
    if term.isColor() then term.setTextColor(colors.gray) end
    print("[kernel] Loading kernel modules ...")

    local Process      = dofile("/kernel/process.lua")
    local Scheduler    = dofile("/kernel/scheduler.lua")
    local Syscall      = dofile("/kernel/syscall.lua")
    local Events       = dofile("/kernel/events.lua")
    local Permissions  = dofile("/kernel/permissions.lua")

    -- Expose globally
    _G.Kernel        = Syscall
    _G.Process       = Process
    _G.Scheduler     = Scheduler
    _G.Events        = Events
    _G.Permissions   = Permissions

    -- Register the BIOS log function with Events so we get kernel logs
    if bios and bios.log then
        Events.subscribe(function(eventType, ...)
            if eventType:sub(1, 7) == "archos_" then
                bios.log("[events] " .. eventType)
            end
        end)
    end

    -- Load core libraries
    print("[kernel] Loading core libraries ...")
    local fs_lib      = require("fs")
    local users_lib   = require("users")
    local crypto_lib  = require("crypto")
    local network_lib = require("network")
    _G.FS       = fs_lib
    _G.Users    = users_lib
    _G.Crypto  = crypto_lib
    _G.Network  = network_lib

    -- Initialize users database
    if users_lib then users_lib.load() end

    -- Initialize PnP drivers
    print("[kernel] Initializing Plug-and-Play drivers ...")
    local driversLoaded = {}
    for _, drvName in ipairs({"pnp", "disk", "monitor", "modem", "printer", "speaker"}) do
        local ok, drv = pcall(require, "drivers/" .. drvName)
        if ok and drv then
            driversLoaded[drvName] = drv
            if drv.init and bios then
                pcall(drv.init, bios.hw)
            end
        end
    end
    _G.Drivers = driversLoaded

    -- Load arch subsystem (pacman + systemd)
    print("[kernel] Loading Arch subsystem ...")
    local pacman_ok, pacman = pcall(dofile, "/lib/arch/pacman.lua")
    if pacman_ok then _G.Pacman = pacman end

    local systemd_ok, systemd = pcall(dofile, "/lib/arch/systemd.lua")
    if systemd_ok and systemd then
        _G.Systemd = systemd
        systemd.init()
    end

    -- Create essential directories
    for _, d in ipairs({"/tmp", "/var/log", "/var/run", "/var/cache", "/var/db", "/proc", "/dev", "/mnt"}) do
        if not fs.exists(d) then fs.makeDir(d) end
    end

    -- Mark kernel as initialized
    _G.KERNEL_READY = true

    print("[kernel] Kernel initialization complete.")
    print("")

    -- Now spawn init (PID 1)
    -- The init process is /sbin/init.lua
    local initPath = "/sbin/init.lua"
    if not fs.exists(initPath) then
        if term.isColor() then term.setTextColor(colors.red) end
        print("[kernel] FATAL: /sbin/init.lua not found!")
        print("[kernel] Spawning emergency shell ...")
        -- Emergency shell
        local function emergencyShell()
            if fs.exists("/bin/sh.lua") then
                dofile("/bin/sh.lua")
            else
                print("[kernel] No shell available. Halting.")
                while true do os.sleep(1) end
            end
        end
        -- Spawn directly (without scheduler) as a fallback
        emergencyShell()
        return
    end

    -- Build init function: load /sbin/init.lua and run it as PID 1
    local function initFunc()
        local ok, initModule = pcall(dofile, initPath)
        if not ok then
            if term.isColor() then term.setTextColor(colors.red) end
            print("[init] Failed to load /sbin/init.lua: " .. tostring(initModule))
            os.sleep(3)
            return 1
        end
        if type(initModule) == "table" and initModule.run then
            initModule.run()
        elseif type(initModule) == "function" then
            initModule()
        else
            print("[init] /sbin/init.lua returned non-callable value")
            return 1
        end
    end

    -- Force PID 1 for init by spawning it explicitly and patching the pid
    local initProc = Process.spawn(initFunc, {
        ppid = 0,
        name = "init",
        user = "root",
        uid  = 0,
        gid  = 0,
        cwd  = "/",
        env = {
            PATH = "/bin:/sbin:/usr/bin:/usr/local/bin",
            HOME = "/root",
            USER = "root",
            TERM = "tty",
            SHELL = "/bin/sh.lua",
            PS1   = "[root@archos /]# ",
        },
    })

    -- Hack: ensure init is at PID 1 (re-assign)
    -- Since Process.spawn uses an internal counter, we swap entries
    if initProc.pid ~= 1 then
        -- Force process table swap
        local real1 = Process.get(1)
        if real1 then
            -- If there's already a PID 1 (unlikely since this is early boot), kill it
            Process.kill(1)
        end
        -- Move our init to PID 1
        local oldPid = initProc.pid
        -- This is hacky; we can't actually renumber pids cleanly.
        -- For now, just leave it and have the scheduler look for "init" by name.
    end

    -- Run scheduler
    print("[kernel] Starting scheduler ...")
    print("")
    if term.isColor() then term.setTextColor(colors.white) end

    -- Spawn the scheduler main loop (blocking)
    -- We'll use a simpler approach: use parallel.waitForAny with the scheduler
    -- and a "shutdown" event watcher.

    local schedulerOk, schedulerErr = Scheduler.main(nil)
    -- Note: Scheduler.main takes an init function, but we already spawned init.
    -- If we passed initFn above, scheduler would spawn a second init at PID 1.
    -- Let's fix that by NOT passing init to scheduler.

    if not schedulerOk then
        if term.isColor() then term.setTextColor(colors.red) end
        print("")
        print("[kernel] Scheduler exited with error: " .. tostring(schedulerErr))
        print("[kernel] System halted.")
        while true do os.sleep(1) end
    end

    -- If we got here, all processes are dead. Halt.
    if term.isColor() then term.setTextColor(colors.yellow) end
    print("[kernel] No processes remaining. System halting.")
    os.sleep(2)
end

-- The bootloader expects a function. Return our main.
return Kernel.main
