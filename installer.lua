--[[
    ArchOS-CC Installer
    ===================
    Downloads and installs the ArchOS-CC operating system from GitHub.

    Usage (in CraftOS shell):
        pastebin run <paste_id_of_installer> <github_user> <github_repo> [branch]
        OR
        wget https://raw.githubusercontent.com/<user>/<repo>/main/installer.lua /installer.lua
        installer <user> <repo> [branch]

    Example:
        installer myuser archos-cc main

    After installation the computer will reboot into the bootloader.
]]

local GITHUB_USER = arg[1] or "your-github-username"
local GITHUB_REPO = arg[2] or "archos-cc"
local GITHUB_BRANCH = arg[3] or "main"
local GITHUB_RAW = "https://raw.githubusercontent.com/" .. GITHUB_USER .. "/" .. GITHUB_REPO .. "/" .. GITHUB_BRANCH .. "/"

-- Colors (Arch Linux TTY palette)
local C = {
    reset   = colors.white,
    head    = colors.lightBlue,
    info    = colors.cyan,
    ok      = colors.green,
    warn    = colors.yellow,
    err     = colors.red,
    dim     = colors.gray,
    accent  = colors.lightGray,
    bg      = colors.black
}

-- Defensive setColor: if c is nil (e.g. from a typo like C.white
-- when the table only has C.reset), just silently skip. Better than
-- crashing the whole installer with "bad argument #1 (number expected,
-- got nil)".
local function setColor(c)
    if c and term.isColor() then
        term.setTextColor(c)
    end
end

-- Helper for colored log lines. Defined early because preflightHTTP()
-- uses it. (In Lua, `local function` is not hoisted - it must appear
-- in the source before the first call.)
local function log(level, msg, color)
    local prefix = ""
    if     level == "ok"   then prefix = " [OK]   "; color = color or C.ok
    elseif level == "err"  then prefix = " [ERR]  "; color = color or C.err
    elseif level == "warn" then prefix = " [WARN] "; color = color or C.warn
    else                        prefix = " [INFO] "; color = color or C.info
    end
    setColor(color)
    term.write(prefix .. msg .. "\n")
end

-- HTTP download with retries and proper timeout.
-- Uses http.request() (async) + os.pullEvent() so we never block forever.
-- CC:Tweaked's http.get() is synchronous and has no built-in timeout,
-- so if GitHub doesn't reply (TLS handshake stuck, blocked domain, etc)
-- the whole computer hangs. This version always times out.
--
-- While waiting for the response, we print a "." every ~2 seconds so
-- the user sees that we're still alive.
local function fetchURL(url, retries, timeoutSec)
    retries = retries or 3
    timeoutSec = timeoutSec or 10
    for attempt = 1, retries do
        -- Issue async request
        http.request(url)
        -- Heartbeat timer: print a dot every 2 seconds so the screen
        -- does not look frozen during slow downloads.
        local heartbeat = os.startTimer(2)
        local deadline = os.startTimer(timeoutSec)
        local body = nil
        local failReason = nil
        while true do
            local ev = { os.pullEvent() }
            if ev[1] == "http_success" and ev[2] == url then
                local handle = ev[3]
                if handle then
                    body = handle.readAll()
                    handle.close()
                end
                os.cancelTimer(heartbeat)
                os.cancelTimer(deadline)
                break
            elseif ev[1] == "http_failure" and ev[2] == url then
                failReason = ev[3] or "request failed"
                os.cancelTimer(heartbeat)
                os.cancelTimer(deadline)
                break
            elseif ev[1] == "timer" and ev[2] == deadline then
                failReason = "timeout after " .. timeoutSec .. "s"
                break
            elseif ev[1] == "timer" and ev[2] == heartbeat then
                -- Heartbeat: print a dot to show we're still alive
                term.write(".")
                heartbeat = os.startTimer(2)
            end
        end
        if body then
            -- Clear heartbeat dots by overwriting with spaces and returning
            return body
        end
        setColor(C.warn)
        term.write(" (retry " .. attempt .. "/" .. retries .. ": " .. tostring(failReason) .. ") ")
        if attempt < retries then os.sleep(0.5 * attempt) end
    end
    return nil
end

local function banner()
    term.clear()
    term.setCursorPos(1, 1)
    setColor(C.head)
    -- Compact banner that fits on a 51x19 Advanced Computer screen.
    print("    ___               ____   ____  _  __")
    print("   /   | ______ __ ___/  _/  / __ \\/ |/ /")
    print("  / /| |/ __/ / // (_-< /    / /_/ /    /  ")
    print(" /_/ |_|/_/  /_//_/___/___/  /____/_/|_/  ")
    setColor(C.accent)
    print(" ArchOS-CC installer - Arch Linux style OS")
    print("")
    setColor(C.dim)
    print(" Repo: " .. GITHUB_USER .. "/" .. GITHUB_REPO .. " @" .. GITHUB_BRANCH)
    print("")
end

-- Pre-flight diagnostic: make sure HTTP works at all before we start
-- downloading 100+ files. This catches the most common CC:Tweaked issues:
--   * http API not enabled in computercraft-server.toml
--   * Domain not in the http whitelist
--   * No internet connection at all
local function preflightHTTP()
    setColor(C.info)
    log("info", "HTTP preflight check ...")
    if not http then
        setColor(C.err)
        log("err", "HTTP API is NOT available on this computer.")
        setColor(C.accent)
        print("")
        print("  To enable HTTP:")
        print("  1. Stop the Minecraft server")
        print("  2. Open config/computercraft-server.toml")
        print("  3. Set [http].enabled = true")
        print("  4. Add raw.githubusercontent.com to [[http.rules]]:")
        print('       { host = "raw.githubusercontent.com", action = "allow" }')
        print('       { host = "*", action = "deny" }')
        print("  5. Restart the server")
        return false
    end
    if not http.request then
        setColor(C.err)
        log("err", "http.request not available (CC:T version too old?)")
        return false
    end

    -- Try a tiny HEAD-like probe with a short timeout
    local probeURL = GITHUB_RAW .. "MANIFEST"
    setColor(C.dim)
    term.write("  probing " .. probeURL .. " ... ")
    local body = fetchURL(probeURL, 1, 8)
    if body then
        setColor(C.ok); print("OK")
        setColor(C.dim); print("    (got " .. #body .. " bytes from MANIFEST)")
        return true
    else
        setColor(C.err); print("FAIL")
        setColor(C.warn)
        print("")
        print("  Cannot reach GitHub. Common causes:")
        print("")
        print("  1. HTTP not enabled in computercraft-server.toml:")
        print('       [http]')
        print('       enabled = true')
        print("")
        print("  2. Domain whitelist blocks raw.githubusercontent.com.")
        print("     Add to [[http.rules]] in computercraft-server.toml:")
        print('       { host = "raw.githubusercontent.com", action = "allow" }')
        print('       { host = "github.com", action = "allow" }')
        print('       { host = "api.github.com", action = "allow" }')
        print('       { host = "*", action = "deny" }')
        print("")
        print("  3. Server has no internet, or firewall blocks HTTPS (port 443).")
        print("")
        print("  4. Repo is private or branch name is wrong.")
        print("     Current: " .. GITHUB_USER .. "/" .. GITHUB_REPO .. " @ " .. GITHUB_BRANCH)
        print("")
        setColor(C.accent)
        print("  Fix the above, then re-run: installer " .. GITHUB_USER .. " " .. GITHUB_REPO .. " " .. GITHUB_BRANCH)
        return false
    end
end

-- File manifest: list of all files (relative paths) that compose the OS.
-- Installer downloads each one in turn.
local MANIFEST = {
    -- Boot chain
    "startup.lua",
    "bios/bios.lua",
    "bootloader/bootloader.lua",
    -- Kernel
    "kernel/init.lua",
    "kernel/process.lua",
    "kernel/scheduler.lua",
    "kernel/syscall.lua",
    "kernel/events.lua",
    "kernel/permissions.lua",
    "kernel/craftos-shim.lua",
    -- Libraries
    "lib/fs.lua",
    "lib/users.lua",
    "lib/crypto.lua",
    "lib/network.lua",
    "lib/drivers/disk.lua",
    "lib/drivers/monitor.lua",
    "lib/drivers/modem.lua",
    "lib/drivers/printer.lua",
    "lib/drivers/speaker.lua",
    "lib/drivers/pnp.lua",
    "lib/arch/pacman.lua",
    "lib/arch/systemd.lua",
    -- Bin (core commands)
    "bin/sh.lua",
    "bin/ls.lua",
    "bin/cd.lua",
    "bin/cat.lua",
    "bin/mv.lua",
    "bin/cp.lua",
    "bin/rm.lua",
    "bin/mkdir.lua",
    "bin/pwd.lua",
    "bin/echo.lua",
    "bin/touch.lua",
    "bin/chmod.lua",
    "bin/chown.lua",
    "bin/useradd.lua",
    "bin/userdel.lua",
    "bin/passwd.lua",
    "bin/su.lua",
    "bin/sudo.lua",
    "bin/mount.lua",
    "bin/umount.lua",
    "bin/dmesg.lua",
    "bin/uname.lua",
    "bin/clear.lua",
    "bin/reboot.lua",
    "bin/poweroff.lua",
    "bin/ifconfig.lua",
    "bin/ping.lua",
    "bin/wget.lua",
    "bin/pastebin.lua",
    "bin/git.lua",
    "bin/pinestore.lua",
    "bin/arch-update.lua",
    "bin/systemctl.lua",
    "bin/pacman.lua",
    "bin/login.lua",
    "bin/which.lua",
    "bin/grep.lua",
    "bin/head.lua",
    "bin/tail.lua",
    "bin/wc.lua",
    "bin/date.lua",
    "bin/whoami.lua",
    "bin/hostname.lua",
    "bin/ps.lua",
    "bin/kill.lua",
    "bin/env.lua",
    "bin/free.lua",
    "bin/df.lua",
    "bin/tree.lua",
    "bin/find.lua",
    -- sbin
    "sbin/init.lua",
    "sbin/fsck.lua",
    "sbin/mkfs.lua",
    "sbin/mkuser.lua",
    "sbin/networkd.lua",
    "sbin/mountd.lua",
    -- usr/bin applications
    "usr/bin/editor.lua",
    "usr/bin/browser.lua",
    "usr/bin/gbrowse.lua",
    "usr/bin/lua-repl.lua",
    "usr/bin/sysmgr.lua",
    "usr/bin/settings.lua",
    "usr/bin/top.lua",
    "usr/bin/neofetch.lua",
    "usr/bin/taskmgr.lua",
    "usr/bin/calculator.lua",
    "usr/bin/notes.lua",
    "usr/bin/player.lua",
    "usr/bin/paint.lua",
    "usr/bin/monitor-app.lua",
    "usr/bin/redstone-panel.lua",
    -- Desktop environments
    "de/tty.lua",
    "de/gnome.lua",
    "de/plasma.lua",
    "de/xfce.lua",
    -- etc configs
    "etc/passwd",
    "etc/group",
    "etc/fstab",
    "etc/hostname",
    "etc/issue",
    "etc/network.conf",
    "etc/os-release",
    "etc/locale/en.lc",
    "etc/shadow",
    "etc/profile",
    -- Docs
    "docs/INSTALL.md",
    "docs/ARCHITECTURE.md",
    "docs/COMMANDS.md",
    "docs/DEVELOPMENT.md",
    -- Top-level
    "README.md",
    "LICENSE",
    ".gitignore",
}

local function ensureDir(path)
    -- path like "/bios" or "/lib/drivers"
    if not fs.exists(path) then
        fs.makeDir(path)
    elseif not fs.isDir(path) then
        error("Path exists but is not a directory: " .. path)
    end
end

local function writeFile(path, content)
    -- Make sure parent directory exists
    local dir = fs.getDir(path)
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local f = fs.open(path, "w")
    if not f then
        return false, "cannot open " .. path .. " for writing"
    end
    f.write(content)
    f.close()
    return true
end

-- Install one file from GitHub
local function installFile(relPath)
    local url = GITHUB_RAW .. relPath
    -- URL-encode spaces just in case
    url = url:gsub(" ", "%%20")
    local body = fetchURL(url)
    if not body then
        return false, "download failed"
    end
    -- Map repo-relative path to in-computer absolute path
    local dest = "/" .. relPath
    local ok, err = writeFile(dest, body)
    if not ok then return false, err end
    return true
end

-- Determine install root. By default we install to / (root of computer).
-- If user passed "test" mode, install to /archos-installer-tmp/
local INSTALL_ROOT = "/"

local function confirm()
    setColor(C.warn)
    term.write("\n  Install ArchOS-CC to " .. INSTALL_ROOT .. "?\n")
    term.write("  Existing files will be overwritten.\n\n")
    setColor(C.accent)
    term.write("  Proceed? [y/N] ")
    setColor(C.reset)
    local ev = read()
    return ev and (ev:lower() == "y" or ev:lower() == "yes")
end

-- Stage 1: collect disk info
local function preflight()
    setColor(C.info)
    log("info", "Disk space check ...")
    local totalSpace = fs.getFreeSpace("/")
    setColor(C.dim)
    print("    Free space at /: " .. tostring(totalSpace) .. " bytes")
    if totalSpace and totalSpace < 100000 then
        log("warn", "Low disk space. Installation may fail.")
    end
    return true
end

-- Stage 2: download manifest
local function downloadManifest()
    setColor(C.info)
    log("info", "Fetching file manifest ...")
    -- We hardcode the manifest in this installer, so no extra fetch needed.
    -- But we also try to fetch a remote MANIFEST file if it exists, so users
    -- can extend the OS without re-uploading installer.
    local remote = fetchURL(GITHUB_RAW .. "MANIFEST", 1)
    if remote then
        -- parse line-by-line
        local extra = {}
        for line in remote:gmatch("[^\r\n]+") do
            local clean = line:gsub("^%s+", ""):gsub("%s+$", "")
            if clean ~= "" and clean:sub(1, 1) ~= "#" then
                extra[#extra+1] = clean
            end
        end
        if #extra > 0 then
            setColor(C.ok)
            log("ok", "Remote MANIFEST loaded: " .. #extra .. " extra files")
            return extra
        end
    end
    setColor(C.dim)
    print("    Using built-in manifest (" .. #MANIFEST .. " files)")
    return MANIFEST
end

-- Stage 3: install each file
-- Each file gets TWO lines:
--   Line 1: "  [1/139] usr/bin/redstone-panel.lua"
--   Line 2: "    > downloading...................... OK  12 KB"
-- This way even on a 51-wide Advanced Computer screen, the path is
-- always fully visible, the user always sees what is being downloaded,
-- and there is a clear OK/FAIL at the end of each file.
local function installAll(fileList)
    local n = #fileList
    local ok, fail = 0, 0
    local failures = {}

    -- Show a clear "starting downloads" banner so the user knows
    -- something is happening even before the first file finishes.
    setColor(C.head)
    print("")
    print("  ============================================")
    print("  Downloading " .. n .. " files ...")
    print("  ============================================")
    print("")

    for i, rel in ipairs(fileList) do
        -- Line 1: counter + file path
        setColor(C.info)
        local counter = string.format("[%d/%d]", i, n)
        -- Path on its own line, with a small indent so it is visually
        -- distinct from the status line below.
        print(string.format("  %s %s", counter, rel))
        -- Line 2: status with heartbeat dots
        setColor(C.dim)
        term.write("    > downloading ")
        -- fetchURL prints "." heartbeats while waiting for HTTP.
        local success, err = installFile(rel)
        if success then
            setColor(C.ok)
            term.write(" OK\n")
            ok = ok + 1
        else
            setColor(C.err)
            term.write(" FAIL\n")
            setColor(C.dim)
            term.write("      reason: " .. tostring(err) .. "\n")
            fail = fail + 1
            failures[#failures+1] = {rel, err}
        end
        -- Yield so the screen actually updates between files.
        os.sleep(0)
    end
    return ok, fail, failures
end

-- Stage 4: post-install configuration
local function postInstall()
    setColor(C.info)
    log("info", "Running post-install hooks ...")

    -- Create runtime dirs
    for _, d in ipairs({"/var/log", "/var/run", "/var/cache", "/home", "/tmp"}) do
        if not fs.exists(d) then fs.makeDir(d) end
    end

    -- Default hostname
    if not fs.exists("/etc/hostname") or fs.getSize("/etc/hostname") == 0 then
        local f = fs.open("/etc/hostname", "w")
        if f then f.write("archos-cc\n"); f.close() end
    end

    -- Create root user if passwd file is empty
    local pf = fs.open("/etc/passwd", "r")
    local passwdContent = ""
    if pf then passwdContent = pf.readAll() or ""; pf.close() end
    if passwdContent == "" or not passwdContent:find("root") then
        setColor(C.warn)
        log("warn", "passwd file empty - generating default root user")
        local f = fs.open("/etc/passwd", "w")
        if f then
            f.write("root:x:0:0:root:/root:/bin/sh.lua\n")
            f.close()
        end
    end

    -- Make /bin/sh.lua the default shell for users
    setColor(C.ok)
    log("ok", "Post-install hooks complete")
end

-- Stage 5: register bootloader as startup
local function registerStartup()
    setColor(C.info)
    log("info", "Registering bootloader as startup ...")
    -- CC:Tweaked runs /startup.lua on boot
    -- Our startup.lua chains into bootloader/bootloader.lua
    -- Already part of manifest. Just verify.
    if fs.exists("/startup.lua") then
        setColor(C.ok); log("ok", "/startup.lua present")
    else
        setColor(C.err); log("err", "/startup.lua missing!")
    end
end

-- Stage 6: first-boot setup (creates root password)
local function firstBootPrompt()
    setColor(C.head)
    print("\n  === First-boot setup ===")
    setColor(C.accent)
    print("  Set a root password (leave empty to skip - insecure!):")
    setColor(C.reset)
    term.write("  root password: ")
    local pw1 = read("*")
    term.write("  confirm:       ")
    local pw2 = read("*")
    if pw1 and pw1 ~= "" and pw1 == pw2 then
        setColor(C.info); log("info", "Hashing password ...")
        -- Load users lib (already installed)
        local users = dofile("/lib/users.lua")
        if users then
            local hash = users.hashPassword(pw1)
            local sf = fs.open("/etc/shadow", "w")
            if sf then
                sf.write("root:" .. hash .. ":0:0:99999:7:::\n")
                sf.close()
            end
            setColor(C.ok); log("ok", "Root password set")
        else
            setColor(C.err); log("err", "Could not load users library")
        end
    else
        setColor(C.warn); log("warn", "Skipped (no root password). Use 'passwd' later.")
    end

    setColor(C.accent)
    print("\n  Select default desktop environment:")
    print("    1) tty      - Arch TTY (text only, minimal)")
    print("    2) gnome     - GNOME-like (simple GUI)")
    print("    3) plasma    - KDE Plasma-like (advanced GUI with effects)")
    print("    4) xfce      - XFCE-like (lightweight GUI)")
    term.write("  choice [1-4, default=1]: ")
    local choice = read()
    local de = "tty"
    if choice == "2" then de = "gnome"
    elseif choice == "3" then de = "plasma"
    elseif choice == "4" then de = "xfce" end
    local f = fs.open("/etc/default-de", "w")
    if f then f.write(de); f.close() end
    setColor(C.ok); log("ok", "Default DE set to: " .. de)
end

-- Main
local function main()
    -- Detect missing arguments BEFORE showing the banner, so the user
    -- sees a clear "how to use" message instead of a broken banner with
    -- placeholder values like "your-github-username".
    if not arg[1] or arg[1] == "" then
        term.clear()
        term.setCursorPos(1, 1)
        if term.isColor() then term.setTextColor(colors.lightBlue) end
        print("    ArchOS-CC Installer")
        if term.isColor() then term.setTextColor(colors.yellow) end
        print("")
        print("  ERROR: no GitHub username specified.")
        print("")
        if term.isColor() then term.setTextColor(colors.white) end
        print("  Usage:")
        print("    installer <github-user> <repo-name> [branch]")
        print("")
        print("  Example:")
        print("    installer Tsundereplan archos-cc main")
        print("")
        if term.isColor() then term.setTextColor(colors.gray) end
        print("  Make sure the repo is PUBLIC and the branch exists.")
        return 1
    end

    banner()

    if not http then
        setColor(C.err)
        print("")
        print("[FATAL] HTTP API is not enabled on this computer.")
        print("        Enable it in computercraft-server.toml:")
        print('          [http]')
        print('          enabled = true')
        print("        Or use a disk-based installation.")
        return 1
    end

    -- Stage 0: preflight HTTP check.
    -- Run BEFORE asking for confirmation so the user sees the
    -- diagnostic immediately, not after typing 'y'.
    setColor(C.head)
    print("  === Stage 0: Pre-flight check ===")
    print("")
    if not preflightHTTP() then
        setColor(C.err)
        print("")
        print("  Pre-flight check failed. Installation aborted.")
        print("  See diagnostics above for how to fix.")
        return 1
    end

    setColor(C.ok)
    print("  HTTP preflight: OK")
    setColor(C.dim)
    print("  GitHub is reachable. Proceeding with installation.")
    print("")
    setColor(C.reset)

    -- Stage 1: confirm with user
    setColor(C.head)
    print("  === Stage 1: Confirm ===")
    print("")
    if not confirm() then
        setColor(C.warn)
        print("")
        print("  Installation cancelled.")
        return 1
    end

    -- Stage 2: disk + manifest
    setColor(C.head)
    print("")
    print("  === Stage 2: Disk check & manifest ===")
    print("")
    preflight()
    local fileList = downloadManifest()

    -- Backup existing startup if present
    if fs.exists("/startup.lua") and not fs.exists("/startup.lua.bak") then
        fs.move("/startup.lua", "/startup.lua.bak")
        setColor(C.dim)
        print("  Backed up existing /startup.lua to /startup.lua.bak")
        print("")
    end

    -- Stage 3: download files (longest stage)
    setColor(C.head)
    print("  === Stage 3: Downloading files ===")
    local ok, fail, failures = installAll(fileList)

    -- Stage 4: summary
    setColor(C.head)
    print("")
    print("  ============================================")
    setColor(C.ok)
    print(string.format("  Installed: %d files", ok))
    if fail > 0 then
        setColor(C.err)
        print(string.format("  Failed:    %d files", fail))
        setColor(C.dim)
        for _, f in ipairs(failures) do
            print("    - " .. f[1] .. ": " .. tostring(f[2]))
        end
    end
    setColor(C.head)
    print("  ============================================")
    print("")

    if fail > 0 and ok == 0 then
        setColor(C.err)
        log("err", "All downloads failed. Check GitHub repo/branch/username.")
        print("    Expected URL pattern: " .. GITHUB_RAW)
        return 1
    end

    -- Stage 5: post-install hooks
    setColor(C.head)
    print("  === Stage 5: Post-install hooks ===")
    print("")
    postInstall()
    print("")

    -- Stage 6: register startup
    setColor(C.head)
    print("  === Stage 6: Register bootloader ===")
    print("")
    registerStartup()
    print("")

    -- Stage 7: first-boot configuration
    setColor(C.head)
    print("  === Stage 7: First-boot setup ===")
    print("")
    firstBootPrompt()
    print("")

    setColor(C.ok)
    print("  ArchOS-CC installed successfully!")
    print("")
    setColor(C.accent)
    print("  Rebooting in 3 seconds ... (press Ctrl+T to abort)")
    print("")
    os.sleep(3)
    os.reboot()
end

return main()
