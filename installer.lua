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

local function setColor(c)
    if term.isColor() then term.setTextColor(c) end
end

local function banner()
    term.clear()
    term.setCursorPos(1, 1)
    setColor(C.head)
    print("    ___                     ____   ____  _  __")
    print("   /   | ______ __ ___     /  _/  / __ \\/ |/ /")
    print("  / /| |/ __/ / // (_-<    / /   / /_/ /    / ")
    print(" /_/ |_|/_/  /_//_/___/   /___/  /____/_/|_/  ")
    setColor(C.accent)
    print("   ComputerCraft Operating System - Arch Linux style")
    print("")
    setColor(C.dim)
    print("  Repository: " .. GITHUB_USER .. "/" .. GITHUB_REPO .. " @ " .. GITHUB_BRANCH)
    print("")
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

local function log(level, msg, color)
    local prefix = ""
    if level == "ok"   then prefix = " [OK]   "; color = color or C.ok
    elseif level == "err"  then prefix = " [ERR]  "; color = color or C.err
    elseif level == "warn" then prefix = " [WARN] "; color = color or C.warn
    else                     prefix = " [INFO] "; color = color or C.info
    end
    setColor(color)
    term.write(prefix .. msg .. "\n")
end

-- HTTP download with retries
local function fetchURL(url, retries)
    retries = retries or 3
    for attempt = 1, retries do
        local h = http.get(url)
        if h then
            local body = h.readAll()
            h.close()
            return body
        end
        setColor(C.warn); term.write(".")
        os.sleep(0.2 * attempt)
    end
    return nil
end

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
    term.write("\n  This will install ArchOS-CC to " .. INSTALL_ROOT .. " on this computer.\n")
    term.write("  All existing files in startup, bios, bootloader, kernel, lib, bin, sbin, usr, de, etc will be overwritten.\n\n")
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
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" and line:sub(1, 1) ~= "#" then
                extra[#extra+1] = line
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
local function installAll(fileList)
    local n = #fileList
    local ok, fail = 0, 0
    local failures = {}
    for i, rel in ipairs(fileList) do
        setColor(C.info)
        term.write(string.format("  [%3d/%3d] %-50s ", i, n, rel))
        local success, err = installFile(rel)
        if success then
            setColor(C.ok); term.write("OK\n")
            ok = ok + 1
        else
            setColor(C.err); term.write("FAIL: " .. tostring(err) .. "\n")
            fail = fail + 1
            failures[#failures+1] = {rel, err}
        end
        -- Flush terminal between files so user sees progress
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
    banner()

    if not http then
        setColor(C.err)
        print("\n[FATAL] HTTP API is not enabled on this computer.")
        print("        Enable it in ComputerCraft.cfg (http.enable=true)")
        print("        or use a disk-based installation.")
        return 1
    end

    if not confirm() then
        setColor(C.warn)
        print("\n  Installation cancelled.")
        return 1
    end

    preflight()
    local fileList = downloadManifest()

    -- Backup existing startup if present
    if fs.exists("/startup.lua") and not fs.exists("/startup.lua.bak") then
        fs.move("/startup.lua", "/startup.lua.bak")
        setColor(C.dim); print("  Backed up existing /startup.lua to /startup.lua.bak")
    end

    local ok, fail, failures = installAll(fileList)

    setColor(C.head)
    print("\n  ============================================")
    setColor(C.ok);   print(string.format("  Installed: %d files", ok))
    if fail > 0 then
        setColor(C.err); print(string.format("  Failed:    %d files", fail))
        setColor(C.dim)
        for _, f in ipairs(failures) do print("    - " .. f[1] .. ": " .. tostring(f[2])) end
    end
    setColor(C.head); print("  ============================================")

    if fail > 0 and ok == 0 then
        setColor(C.err)
        log("err", "All downloads failed. Check GitHub repo/branch/username.")
        print("    Expected URL pattern: " .. GITHUB_RAW)
        return 1
    end

    postInstall()
    registerStartup()
    firstBootPrompt()

    setColor(C.ok)
    print("\n  ArchOS-CC installed successfully!")
    setColor(C.accent)
    print("  Rebooting in 3 seconds ... (press Ctrl+T to abort)")
    os.sleep(3)
    os.reboot()
end

return main()
