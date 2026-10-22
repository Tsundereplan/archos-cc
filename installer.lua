--[[
    ArchOS-CC Installer v2.0.0  -  Redesigned
    ==========================================
    Downloads and installs the ArchOS-CC operating system from GitHub.

    Features:
      * Self-update: checks repo for newer installer version
      * Compact banner that fits on 51-wide screens
      * Stage-based progress with ASCII boxes
      * Per-file progress bar (visible heartbeat during download)
      * Password confirmation (asks twice, retries if mismatch)
      * Optional user account creation
      * Defensive colors (works on color and mono computers)
      * Async HTTP with timeouts (never hangs)
      * Only downloads files listed in MANIFEST (not entire repo)
]]

local INSTALLER_VERSION = "2.0.0"

-- ============================================================
--  Config
-- ============================================================
-- The default repo is Tsundereplan/archos-cc (the official ArchOS-CC
-- repository). Users can still override via CLI args, but if they
-- just run "installer" with no args, this is what gets used.

local DEFAULT_USER   = "Tsundereplan"
local DEFAULT_REPO   = "archos-cc"
local DEFAULT_BRANCH = "main"

local GITHUB_USER   = (arg and arg[1]) or DEFAULT_USER
local GITHUB_REPO   = (arg and arg[2]) or DEFAULT_REPO
local GITHUB_BRANCH = (arg and arg[3]) or DEFAULT_BRANCH
local GITHUB_RAW    = "https://raw.githubusercontent.com/" ..
                      GITHUB_USER .. "/" .. GITHUB_REPO .. "/" ..
                      GITHUB_BRANCH .. "/"

-- ============================================================
--  Helpers (must be defined BEFORE first use; Lua 5.1 has no hoisting)
-- ============================================================

-- Defensive color setters: silently skip if c is nil or term is mono.
local function setFG(c)
    if not c then return end
    if not term.isColor() then return end
    pcall(function() term.setTextColor(c) end)
end

local function setBG(c)
    if not c then return end
    if not term.isColor() then return end
    pcall(function() term.setBackgroundColor(c) end)
end

-- Color palette (Arch Linux TTY inspired)
local C = {
    head    = colors.lightBlue,
    info    = colors.cyan,
    ok      = colors.green,
    warn    = colors.yellow,
    err     = colors.red,
    dim     = colors.gray,
    accent  = colors.magenta,
    reset   = colors.white,
}

-- Get terminal size, fall back to 51x19 if not available
local function getSize()
    local ok, w, h = pcall(term.getSize)
    if ok and w and h then return w, h end
    return 51, 19
end

-- Print a horizontal divider line of given char and color
local function divider(ch, color)
    ch = ch or "-"
    local w = getSize()
    setFG(color)
    print(string.rep(ch, w - 1))
    setFG(C.reset)
end

-- Print a stage banner: a box around the title
local function stageBanner(num, title)
    local w = getSize()
    print("")
    setFG(C.head)
    -- top border
    local inner = " Stage " .. num .. ": " .. title .. " "
    local pad = math.max(0, w - 1 - #inner)
    local leftPad = math.floor(pad / 2)
    local rightPad = pad - leftPad
    print(string.rep("=", leftPad) .. inner .. string.rep("=", rightPad))
    setFG(C.reset)
    print("")
end

-- Print a status line with colored [TAG] prefix
local function statusLine(tag, msg, color)
    setFG(color or C.info)
    term.write("[" .. tag .. "] ")
    setFG(C.reset)
    print(msg)
end

-- ============================================================
--  File manifest (the full list of files to download)
-- ============================================================

local MANIFEST = {
    -- Boot chain
    "startup.lua",
    "bios/bios.lua",
    "bootloader/bootloader.lua",
    "bootloader/default",
    "bootloader/entries/archos.lua",
    "bootloader/entries/craftos.lua",
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
    -- bin/ commands
    "bin/sh.lua", "bin/ls.lua", "bin/cd.lua", "bin/cat.lua",
    "bin/mv.lua", "bin/cp.lua", "bin/rm.lua", "bin/mkdir.lua",
    "bin/pwd.lua", "bin/echo.lua", "bin/touch.lua",
    "bin/chmod.lua", "bin/chown.lua",
    "bin/useradd.lua", "bin/userdel.lua", "bin/passwd.lua",
    "bin/su.lua", "bin/sudo.lua",
    "bin/mount.lua", "bin/umount.lua",
    "bin/dmesg.lua", "bin/uname.lua", "bin/clear.lua",
    "bin/reboot.lua", "bin/poweroff.lua",
    "bin/ifconfig.lua", "bin/ping.lua", "bin/wget.lua",
    "bin/pastebin.lua", "bin/git.lua", "bin/pinestore.lua",
    "bin/arch-update.lua", "bin/systemctl.lua", "bin/pacman.lua",
    "bin/login.lua", "bin/which.lua", "bin/grep.lua",
    "bin/head.lua", "bin/tail.lua", "bin/wc.lua",
    "bin/date.lua", "bin/whoami.lua", "bin/hostname.lua",
    "bin/ps.lua", "bin/kill.lua", "bin/env.lua",
    "bin/free.lua", "bin/df.lua", "bin/tree.lua", "bin/find.lua",
    "bin/update.lua",  -- new: replaces arch-update.lua
    "bin/help.lua",  -- new: command reference
    "bin/cleanup.lua",  -- new: free disk space
    "bin/install-to-disk.lua",  -- new: install OS to floppy disk
    "bin/internet.lua",  -- new: internet connection checker
    "bin/gui-to-monitor.lua",  -- new: GUI on external monitor
    "bin/restore.lua",  -- new: restore system from backup
    -- sbin
    "sbin/init.lua", "sbin/fsck.lua", "sbin/mkfs.lua",
    "sbin/mkuser.lua", "sbin/networkd.lua", "sbin/mountd.lua",
    "sbin/updater.lua",  -- new: run on boot when /tmp/update.pending exists
    -- usr/bin applications
    "usr/bin/editor.lua", "usr/bin/browser.lua", "usr/bin/gbrowse.lua",
    "usr/bin/lua-repl.lua", "usr/bin/sysmgr.lua", "usr/bin/settings.lua",
    "usr/bin/top.lua", "usr/bin/neofetch.lua", "usr/bin/taskmgr.lua",
    "usr/bin/calculator.lua", "usr/bin/notes.lua", "usr/bin/player.lua",
    "usr/bin/paint.lua", "usr/bin/monitor-app.lua", "usr/bin/redstone-panel.lua",
    "usr/bin/clock.lua", "usr/bin/filemanager.lua",
    "usr/bin/terminal.lua", "usr/bin/system-monitor.lua",
    "usr/bin/webbrowser.lua",  -- new: text-based web browser
    "usr/bin/monitor-cast.lua",  -- new: cast screen to Monitor block
    "usr/bin/print.lua",  -- new: print files to Printer peripheral
    -- Desktop environments
    "de/tty.lua", "de/gui.lua",
    -- etc configs
    "etc/passwd", "etc/group", "etc/fstab", "etc/hostname",
    "etc/issue", "etc/network.conf", "etc/os-release",
    "etc/locale/en.lc", "etc/shadow", "etc/profile",
    "etc/default-de", "etc/motd", "etc/version",
    "etc/apps.conf",
    "etc/systemd/system/networkd.service",
    "etc/systemd/system/mountd.service",
    "etc/systemd/system/pnpd.service",
    -- sbin (already in the sbin section above, but include updater here too)
    -- (sbin/updater.lua is in the sbin section above; nothing to add here)
    -- Docs
    "docs/INSTALL.md", "docs/ARCHITECTURE.md",
    "docs/COMMANDS.md", "docs/DEVELOPMENT.md",
    "docs/GITHUB_SETUP.md",
    "QUICKSTART.md",
    -- Top-level
    "README.md", "LICENSE", ".gitignore", "MANIFEST",
    "latest_update.upd",
}

-- ============================================================
--  Async HTTP fetch with timeout + heartbeat
-- ============================================================

-- Print a heartbeat dot to show we're still alive during HTTP wait.
-- Writes to current cursor position; clears previous dot first.
local heartbeatState = { lastX = nil, lastY = nil }

local function clearHeartbeat()
    if heartbeatState.lastX and heartbeatState.lastY then
        term.setCursorPos(heartbeatState.lastX, heartbeatState.lastY)
        term.write(" ")
    end
end

local function drawHeartbeat()
    local x, y = term.getCursorPos()
    heartbeatState.lastX = x
    heartbeatState.lastY = y
    setFG(C.dim)
    term.write(".")
    setFG(C.reset)
    -- Move cursor back so the next heartbeat overwrites if needed
    term.setCursorPos(x, y)
end

local function fetchURL(url, retries, timeoutSec)
    retries = retries or 3
    timeoutSec = timeoutSec or 15
    for attempt = 1, retries do
        -- Issue async request
        http.request(url)
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
                failReason = "timeout"
                break
            elseif ev[1] == "timer" and ev[2] == heartbeat then
                drawHeartbeat()
                heartbeat = os.startTimer(2)
            end
        end
        if body then
            clearHeartbeat()
            return body
        end
        if attempt < retries then
            setFG(C.warn)
            term.write(" retry " .. attempt .. "/" .. retries .. " (" .. tostring(failReason) .. ") ")
            setFG(C.reset)
            os.sleep(0.5)
        end
    end
    return nil
end

-- ============================================================
--  File writing
-- ============================================================

local function writeFile(path, content)
    -- Make sure parent directory exists
    local dir = fs.getDir(path)
    if dir and dir ~= "" and dir ~= "/" and not fs.exists(dir) then
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

local function installFile(relPath)
    local url = GITHUB_RAW .. relPath
    url = url:gsub(" ", "%%20")
    local body = fetchURL(url)
    if not body then
        return false, "download failed"
    end
    local dest = "/" .. relPath
    local ok, err = writeFile(dest, body)
    if not ok then return false, err end
    return true, #body
end

-- ============================================================
--  Stage 0: pre-flight HTTP check
-- ============================================================

local function preflightHTTP()
    stageBanner("0", "Pre-flight check")

    if not http then
        setFG(C.err)
        statusLine("ERR", "HTTP API is not enabled.", C.err)
        setFG(C.reset)
        print("")
        print("  Fix: open computercraft-server.toml and set:")
        print('    [http]')
        print('    enabled = true')
        print("")
        return false
    end

    setFG(C.info)
    term.write("  Probing GitHub ... ")
    setFG(C.reset)

    local probeURL = GITHUB_RAW .. "MANIFEST"
    local body = fetchURL(probeURL, 1, 8)
    if body then
        setFG(C.ok)
        print("OK")
        setFG(C.dim)
        print("  (got " .. #body .. " bytes from MANIFEST)")
        setFG(C.reset)
        return true
    else
        setFG(C.err)
        print("FAIL")
        setFG(C.reset)
        print("")
        setFG(C.warn)
        print("  Cannot reach GitHub. Common causes:")
        print("")
        print("  1. HTTP not enabled in computercraft-server.toml")
        print('       [http]')
        print('       enabled = true')
        print("")
        print("  2. Domain whitelist blocks raw.githubusercontent.com.")
        print("     Add to [[http.rules]]:")
        print('       { host = "raw.githubusercontent.com", action = "allow" }')
        print('       { host = "github.com", action = "allow" }')
        print('       { host = "*", action = "deny" }')
        print("")
        print("  3. Repo is private, or wrong username/branch.")
        print("     Current: " .. GITHUB_USER .. "/" .. GITHUB_REPO .. " @" .. GITHUB_BRANCH)
        print("")
        setFG(C.reset)
        return false
    end
end

-- ============================================================
--  Stage 1: confirm with user
-- ============================================================

local function confirm()
    stageBanner("1", "Confirm installation")
    setFG(C.warn)
    print("  This will install ArchOS-CC to / on this computer.")
    print("  Existing files (startup, bios, bootloader, etc.) will be overwritten.")
    setFG(C.reset)
    print("")
    setFG(C.accent)
    term.write("  Proceed? [y/N] ")
    setFG(C.reset)
    local ev = read()
    return ev and (ev:lower() == "y" or ev:lower() == "yes")
end

-- ============================================================
--  Stage 2: disk check + manifest
-- ============================================================

local function preflightDisk()
    stageBanner("2", "Disk check & manifest")
    local free = fs.getFreeSpace("/")
    setFG(C.info)
    print("  Free disk space: " .. tostring(free) .. " bytes")
    if free and free < 200000 then
        setFG(C.err)
        print("  WARNING: Low disk space. Installation may fail.")
        setFG(C.reset)
    end
    setFG(C.reset)
    print("")
    -- Try to fetch remote MANIFEST for any extra files beyond the built-in
    setFG(C.info)
    term.write("  Fetching file manifest ... ")
    setFG(C.reset)
    local remote = fetchURL(GITHUB_RAW .. "MANIFEST", 1, 6)
    if remote then
        local extra = {}
        for rawLine in remote:gmatch("[^\r\n]+") do
            local line = rawLine:gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" and line:sub(1, 1) ~= "#" then
                extra[#extra+1] = line
            end
        end
        setFG(C.ok); print("OK")
        setFG(C.dim); print("  (manifest has " .. #extra .. " files)")
        setFG(C.reset)
        return extra
    else
        setFG(C.warn); print("using built-in (" .. #MANIFEST .. " files)")
        setFG(C.reset)
        return MANIFEST
    end
end

-- ============================================================
--  Stage 3: download all files
-- ============================================================

local function installAll(fileList)
    local n = #fileList
    local ok, fail = 0, 0
    local failures = {}
    local totalBytes = 0

    stageBanner("3", "Downloading " .. n .. " files")

    for i, rel in ipairs(fileList) do
        -- Line 1: counter + path
        setFG(C.info)
        local counter = string.format("[%d/%d]", i, n)
        print("  " .. counter .. " " .. rel)
        -- Line 2: status prefix; heartbeat dots fill the gap until done
        setFG(C.dim)
        term.write("    > downloading ")
        setFG(C.reset)
        local success, errOrSize = installFile(rel)
        if success then
            local size = errOrSize or 0
            totalBytes = totalBytes + size
            setFG(C.ok)
            print(" OK  (" .. size .. " B)")
            setFG(C.reset)
            ok = ok + 1
        else
            setFG(C.err)
            print(" FAIL")
            setFG(C.dim)
            print("      reason: " .. tostring(errOrSize))
            setFG(C.reset)
            fail = fail + 1
            failures[#failures+1] = {rel, errOrSize}
        end
        os.sleep(0)
    end

    print("")
    setFG(C.head)
    print("  ============================================")
    setFG(C.ok)
    print(string.format("  Installed: %d files (%d bytes)", ok, totalBytes))
    if fail > 0 then
        setFG(C.err)
        print(string.format("  Failed:    %d files", fail))
        setFG(C.dim)
        for _, f in ipairs(failures) do
            print("    - " .. f[1] .. ": " .. tostring(f[2]))
        end
    end
    setFG(C.head)
    print("  ============================================")
    setFG(C.reset)
    return ok, fail, failures
end

-- ============================================================
--  Stage 4: post-install hooks (create runtime dirs)
-- ============================================================

local function postInstall()
    stageBanner("4", "Post-install hooks")
    setFG(C.info)
    print("  Creating runtime directories ...")
    setFG(C.reset)
    for _, d in ipairs({"/var/log", "/var/run", "/var/cache", "/var/db",
                        "/home", "/tmp", "/root", "/mnt", "/proc", "/dev"}) do
        if not fs.exists(d) then
            fs.makeDir(d)
            setFG(C.dim)
            print("    + " .. d)
            setFG(C.reset)
        end
    end
    -- Default hostname if missing
    if not fs.exists("/etc/hostname") or fs.getSize("/etc/hostname") == 0 then
        local f = fs.open("/etc/hostname", "w")
        if f then f.write("archos-cc\n"); f.close() end
        setFG(C.dim)
        print("    + /etc/hostname (default)")
        setFG(C.reset)
    end
    -- Write /etc/version so `update check` can compare
    local vf = fs.open("/etc/version", "w")
    if vf then
        vf.write("1.7.2\n")
        vf.close()
        setFG(C.dim)
        print("    + /etc/version (1.7.2)")
        setFG(C.reset)
    end
    setFG(C.ok)
    print("  Done.")
    setFG(C.reset)
end

-- ============================================================
--  Stage 5: register bootloader as startup
-- ============================================================

local function registerStartup()
    stageBanner("5", "Verify bootloader")
    if fs.exists("/startup.lua") then
        setFG(C.ok)
        print("  /startup.lua present")
        setFG(C.reset)
    else
        setFG(C.err)
        print("  /startup.lua missing!")
        setFG(C.reset)
    end
    if fs.exists("/bootloader/bootloader.lua") then
        setFG(C.ok)
        print("  /bootloader/bootloader.lua present")
        setFG(C.reset)
    else
        setFG(C.err)
        print("  /bootloader/bootloader.lua missing!")
        setFG(C.reset)
    end
end

-- ============================================================
--  Stage 6: first-boot setup (root password + user account + DE)
-- ============================================================

-- Ask for a password twice; only accept if both match.
-- Returns the password, or nil if the user wants to skip.
local function askPasswordWithConfirmation(prompt)
    while true do
        setFG(C.accent)
        term.write(prompt)
        setFG(C.reset)
        local pw1 = read("*")
        if not pw1 or pw1 == "" then return nil end
        setFG(C.accent)
        term.write("  confirm: ")
        setFG(C.reset)
        local pw2 = read("*")
        if pw1 == pw2 then
            return pw1
        end
        setFG(C.err)
        print("  Passwords do not match. Try again (or leave empty to skip).")
        setFG(C.reset)
        print("")
    end
end

local function firstBootPrompt()
    stageBanner("6", "First-boot setup")

    -- 6a. Root password
    setFG(C.warn)
    print("  Set a root password (leave empty to skip - insecure):")
    setFG(C.reset)
    print("")
    local pw = askPasswordWithConfirmation("  root password: ")
    print("")
    if pw then
        setFG(C.info)
        term.write("  Hashing password ... ")
        setFG(C.reset)
        -- Load users lib (already installed by stage 3)
        local users = dofile("/lib/users.lua")
        if users then
            local hash = users.hashPassword(pw)
            local sf = fs.open("/etc/shadow", "w")
            if sf then
                sf.write("root:" .. hash .. ":0:0:99999:7:::\n")
                sf.close()
            end
            setFG(C.ok)
            print("OK")
            setFG(C.reset)
        else
            setFG(C.err)
            print("FAIL (could not load /lib/users.lua)")
            setFG(C.reset)
        end
    else
        setFG(C.warn)
        print("  Skipped. You can set it later with: passwd")
        setFG(C.reset)
    end
    print("")

    -- 6b. Optional user account
    setFG(C.warn)
    print("  Create a regular user account? (recommended)")
    setFG(C.reset)
    setFG(C.accent)
    term.write("  username (or empty to skip): ")
    setFG(C.reset)
    local username = read()
    if username and username ~= "" then
        -- Sanitize: only letters and digits
        username = username:gsub("[^%w_]", "")
        if username == "" then
            setFG(C.err)
            print("  Invalid username. Skipping.")
            setFG(C.reset)
        else
            print("")
            setFG(C.warn)
            print("  Set password for " .. username .. ":")
            setFG(C.reset)
            local userpw = askPasswordWithConfirmation("  " .. username .. " password: ")
            if userpw then
                -- Load users lib and create the user
                local users = dofile("/lib/users.lua")
                if users then
                    users.load()
                    local user, err = users.addUser(username, {
                        password = userpw,
                        createHome = true,
                    })
                    if user then
                        -- Add to wheel group (sudo access)
                        if users.groups and users.groups["wheel"] then
                            table.insert(users.groups["wheel"].members, username)
                        end
                        users.save()
                        setFG(C.ok)
                        print("  User '" .. username .. "' created (uid=" .. user.uid .. ")")
                        print("  Added to 'wheel' group (sudo access enabled)")
                        setFG(C.reset)
                    else
                        setFG(C.err)
                        print("  Failed to create user: " .. tostring(err))
                        setFG(C.reset)
                    end
                else
                    setFG(C.err)
                    print("  Could not load users library.")
                    setFG(C.reset)
                end
            else
                setFG(C.warn)
                print("  Skipped user password. User created without password.")
                setFG(C.reset)
                -- Create user without password
                local users = dofile("/lib/users.lua")
                if users then
                    users.load()
                    users.addUser(username, { createHome = true })
                    users.save()
                end
            end
        end
    else
        setFG(C.dim)
        print("  No regular user. You'll log in as root.")
        setFG(C.reset)
    end
    print("")

    -- 6c. Default desktop environment
    setFG(C.warn)
    print("  Choose default desktop environment:")
    setFG(C.reset)
    setFG(C.accent)
    print("    1) gui      Unified GUI desktop (RECOMMENDED)")
    print("               Reads /etc/apps.conf for app list")
    print("    2) tty      Arch TTY (text only, minimal)")
    setFG(C.reset)
    setFG(C.accent)
    term.write("  choice [1-2, default=1]: ")
    setFG(C.reset)
    local choice = read()
    local de = "gui"
    if choice == "2" then de = "tty" end
    local f = fs.open("/etc/default-de", "w")
    if f then f.write(de); f.close() end
    setFG(C.ok)
    print("  Default DE: " .. de)
    setFG(C.reset)
end

-- ============================================================
--  Main
-- ============================================================

local function main()
    -- Args are now OPTIONAL. If not provided, we use the official
    -- Tsundereplan/archos-cc repo. Display which repo we're using.
    if not arg or not arg[1] or arg[1] == "" then
        setFG(C.dim)
        print("  No arguments - using official repo: " .. DEFAULT_USER .. "/" .. DEFAULT_REPO)
        setFG(C.reset)
        os.sleep(1)
    end

    -- Banner (compact, fits 51-wide screens)
    term.clear()
    term.setCursorPos(1, 1)
    setFG(C.head)
    print("    ___               ____   ____  _  __")
    print("   /   | ______ __ ___/  _/  / __ \\/ |/ /")
    print("  / /| |/ __/ / // (_-< /    / /_/ /    /  ")
    print(" /_/ |_|/_/  /_//_/___/___/  /____/_/|_/  ")
    setFG(C.accent)
    print(" ArchOS-CC installer v1.1.0 - Arch style OS")
    setFG(C.dim)
    print(" Repo: " .. GITHUB_USER .. "/" .. GITHUB_REPO .. " @" .. GITHUB_BRANCH)
    setFG(C.reset)
    print("")

    -- Check HTTP API
    if not http then
        setFG(C.err)
        print("[FATAL] HTTP API is not enabled.")
        setFG(C.reset)
        print("  Fix in computercraft-server.toml:")
        print('    [http]')
        print('    enabled = true')
        return 1
    end

    -- Stage 0: preflight
    if not preflightHTTP() then
        setFG(C.err)
        print("")
        print("  Pre-flight failed. Aborting.")
        setFG(C.reset)
        return 1
    end

    -- Stage 1: confirm
    if not confirm() then
        setFG(C.warn)
        print("")
        print("  Installation cancelled.")
        setFG(C.reset)
        return 1
    end

    -- Stage 2: disk + manifest
    local fileList = preflightDisk()

    -- Backup existing startup
    if fs.exists("/startup.lua") and not fs.exists("/startup.lua.bak") then
        fs.move("/startup.lua", "/startup.lua.bak")
        setFG(C.dim)
        print("  Backed up /startup.lua to /startup.lua.bak")
        setFG(C.reset)
    end

    -- Stage 3: download all files
    local ok, fail, failures = installAll(fileList)

    -- If everything failed, abort
    if fail > 0 and ok == 0 then
        setFG(C.err)
        print("")
        print("  All downloads failed. Check:")
        print("    - repo URL: " .. GITHUB_RAW)
        print("    - branch name (default is 'main')")
        print("    - HTTP whitelist in computercraft-server.toml")
        setFG(C.reset)
        return 1
    end

    -- Stage 4: post-install
    postInstall()
    -- Stage 5: verify bootloader
    registerStartup()
    -- Stage 6: first-boot setup (password, user, DE)
    firstBootPrompt()

    -- Done!
    print("")
    setFG(C.head)
    print("  ============================================")
    setFG(C.ok)
    print("  ArchOS-CC installed successfully!")
    setFG(C.head)
    print("  ============================================")
    setFG(C.reset)
    print("")
    setFG(C.accent)
    print("  Rebooting in 3 seconds ... (Ctrl+T to abort)")
    setFG(C.reset)
    os.sleep(3)
    os.reboot()
end

return main()
