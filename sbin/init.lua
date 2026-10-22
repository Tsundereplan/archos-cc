--[[
    sbin/init.lua  —  User-space init process (PID 1)
    =================================================
    Equivalent to systemd on Arch Linux. Run as PID 1 by the kernel.
    Responsibilities:
      * Mount filesystems from /etc/fstab
      * Bring up network interfaces
      * Start enabled services (systemd-like)
      * Start a getty/login process on the main terminal
      * Reap orphan processes (become their parent)

    After init finishes setup, it sits in an event loop, listening for:
      * archos_shutdown / archos_reboot events
      * service crashes (to restart per Restart= config)
      * new login session requests
]]

local Init = {}

function Init.run()
    local Kernel = _G.Kernel
    local Events = _G.Events

    -- Print init banner
    if term.isColor() then term.setTextColor(colors.lightBlue) end
    print("")
    print("    Welcome to ArchOS-CC!")
    if term.isColor() then term.setTextColor(colors.gray) end
    print("    ===========================")
    print("")

    -- Load users database
    if _G.Users then
        _G.Users.ensureRoot()
    end

    -- Parse and mount filesystems from /etc/fstab
    if term.isColor() then term.setTextColor(colors.gray) end
    print("[init] Mounting filesystems ...")
    if fs.exists("/etc/fstab") then
        local f = fs.open("/etc/fstab", "r")
        if f then
            for line in f.readLine do
                if line and line ~= "" and line:sub(1, 1) ~= "#" then
                    local mp, dev, opts = line:match("^%s*([^%s]+)%s+([^%s]+)%s+([^%s]+)")
                    if mp and dev then
                        if dev ~= "<root>" and fs.exists(dev) then
                            if _G.FS then
                                _G.FS.mount(mp, dev, opts)
                            end
                            if term.isColor() then term.setTextColor(colors.green) end
                            print("  [OK] " .. mp .. " -> " .. dev)
                            if term.isColor() then term.setTextColor(colors.gray) end
                        end
                    end
                end
            end
            f.close()
        end
    end

    -- Bring up network
    print("[init] Bringing up network ...")
    if _G.Network then
        local ok, err = _G.Network.init()
        if ok then
            if term.isColor() then term.setTextColor(colors.green) end
            print("  [OK] Network online (" .. _G.Network.hostname .. ")")
            if term.isColor() then term.setTextColor(colors.gray) end
        else
            if term.isColor() then term.setTextColor(colors.yellow) end
            print("  [WARN] Network init: " .. tostring(err))
            if term.isColor() then term.setTextColor(colors.gray) end
        end
    end

    -- Start enabled services
    print("[init] Starting services ...")
    if _G.Systemd then
        _G.Systemd.init()
    end

    -- Create essential runtime files
    if not fs.exists("/var/run/utmp") then
        local f = fs.open("/var/run/utmp", "w"); if f then f.close() end
    end

    -- Decide if we go to graphical or text mode
    local de = "tty"
    if fs.exists("/etc/default-de") then
        local f = fs.open("/etc/default-de", "r")
        if f then
            de = (f.readAll() or "tty"):gsub("^%s+", ""):gsub("%s+$", "")
            f.close()
        end
    end

    print("[init] Spawning login ...")
    print("")

    if term.isColor() then term.setTextColor(colors.white) end

    -- Main init loop: spawn gettys/login repeatedly
    while true do
        -- Spawn the login process
        local loginPath = "/bin/login.lua"
        if not fs.exists(loginPath) then
            loginPath = "/bin/sh.lua"  -- fallback
        end

        -- Decide whether to boot straight to DE or to a login prompt
        local entryPath = "/bin/login.lua"
        if de ~= "tty" and fs.exists("/de/" .. de .. ".lua") then
            entryPath = "/de/" .. de .. ".lua"
        end

        local pid = Kernel.exec(entryPath, {})
        if pid then
            -- Wait for it to finish (login shell exits on logout)
            Kernel.wait(pid)
        else
            print("[init] Failed to spawn login. Retrying in 3s...")
            os.sleep(3)
        end

        -- On DE exit, loop back and restart the same DE
        -- (GUI will show login screen again, no need to fall back to tty)
    end
end

return Init
