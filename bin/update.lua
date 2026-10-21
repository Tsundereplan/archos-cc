--[[
    bin/update.lua  —  ArchOS-CC Update Manager
    ==========================================
    Checks for and installs updates from the official ArchOS-CC repository.

    Usage:
        update                  Default: same as 'update check'
        update check            Check if an update is available
        update install          Install available update (with backup option)
        update ver              Show current and latest versions
        update wn               Show What's New for the latest update
        update repo             Show current repository URL
        update repo <url>       Switch to a different repository
        update repo default     Switch back to the official Tsundereplan/archos-cc repo

    Update metadata file (latest_update.upd on the repo):
        [version]
        1.2.0
        [date]
        2026-01-15
        [whatsnew]
        - Fixed login bug
        - Added GRUB-like bootloader
        - New update command
        [/whatsnew]
        [files]
        bin/login.lua
        bin/update.lua
        bootloader/bootloader.lua
        kernel/scheduler.lua
        [/files]

    The update process:
      1. update check    -> reads latest_update.upd from repo, compares
                            with local /etc/version. Shows available update
                            or "system is up to date".
      2. update install  -> asks "Create backup before update? [Y/n]"
                            If yes: copies system to /backup/archos-<timestamp>/
                            Then reboots into update mode.
      3. Update mode      -> on boot, kernel detects /tmp/update.pending
                            and runs the updater before init.
]]

-- Default official repo
local DEFAULT_USER   = "Tsundereplan"
local DEFAULT_REPO   = "archos-cc"
local DEFAULT_BRANCH = "main"
local DEFAULT_RAW    = "https://raw.githubusercontent.com/" ..
                       DEFAULT_USER .. "/" .. DEFAULT_REPO .. "/" ..
                       DEFAULT_BRANCH .. "/"

-- Load configured repo from /etc/update.repo if present
local function getCurrentRepo()
    if fs.exists("/etc/update.repo") then
        local f = fs.open("/etc/update.repo", "r")
        if f then
            local url = f.readAll()
            f.close()
            url = url:gsub("^%s+", ""):gsub("%s+$", "")
            if url ~= "" then return url end
        end
    end
    return DEFAULT_RAW
end

local function saveCurrentRepo(url)
    if not fs.exists("/etc") then fs.makeDir("/etc") end
    local f = fs.open("/etc/update.repo", "w")
    if f then f.write(url); f.close() end
end

-- Read the current system version from /etc/version
local function getCurrentVersion()
    if not fs.exists("/etc/version") then return "0.0.0" end
    local f = fs.open("/etc/version", "r")
    if not f then return "0.0.0" end
    local v = f.readAll()
    f.close()
    v = v:gsub("^%s+", ""):gsub("%s+$", "")
    return v
end

-- Fetch the latest_update.upd file from the repo and parse it.
-- Returns a table: { version=..., date=..., whatsnew=..., files={...} }
local function fetchUpdateInfo(repoURL)
    if not http then return nil, "HTTP API not enabled" end

    local function fetch(url, timeout)
        timeout = timeout or 10
        http.request(url)
        local timer = os.startTimer(timeout)
        while true do
            local ev = { os.pullEvent() }
            if ev[1] == "http_success" and ev[2] == url then
                local handle = ev[3]
                if handle then
                    local body = handle.readAll()
                    handle.close()
                    os.cancelTimer(timer)
                    return body
                end
                os.cancelTimer(timer)
                return nil
            elseif ev[1] == "http_failure" and ev[2] == url then
                os.cancelTimer(timer)
                return nil, ev[3] or "request failed"
            elseif ev[1] == "timer" and ev[2] == timer then
                return nil, "timeout"
            end
        end
    end

    local body, err = fetch(repoURL .. "latest_update.upd")
    if not body then return nil, err end

    -- Parse the .upd file
    local info = { version = "?", date = "?", whatsnew = "", files = {} }
    local section = nil
    local whatsnew_lines = {}
    for rawLine in body:gmatch("[^\r\n]+") do
        local line = rawLine:gsub("^%s+", ""):gsub("%s+$", "")
        if line:sub(1, 1) == "[" and line:sub(-1) == "]" then
            section = line:sub(2, -2):lower()
        elseif section == "version" then
            info.version = line
        elseif section == "date" then
            info.date = line
        elseif section == "whatsnew" then
            if line ~= "" and line:lower() ~= "[/whatsnew]" then
                table.insert(whatsnew_lines, line)
            end
        elseif section == "files" then
            if line ~= "" and line:lower() ~= "[/files]" then
                table.insert(info.files, line)
            end
        end
    end
    info.whatsnew = table.concat(whatsnew_lines, "\n")
    return info
end

-- Compare two version strings like "1.2.3"
local function versionCompare(a, b)
    local function parse(v)
        local parts = {}
        for n in v:gmatch("%d+") do table.insert(parts, tonumber(n)) end
        return parts
    end
    local pa, pb = parse(a), parse(b)
    for i = 1, math.max(#pa, #pb) do
        local na, nb = pa[i] or 0, pb[i] or 0
        if na < nb then return -1 end
        if na > nb then return 1 end
    end
    return 0
end

-- Pretty colors
local function setFG(c)
    if c and term.isColor() then
        pcall(function() term.setTextColor(c) end)
    end
end

local function printOK(msg)   setFG(colors.green);  print(msg); setFG(colors.white) end
local function printErr(msg)  setFG(colors.red);    print(msg); setFG(colors.white) end
local function printWarn(msg) setFG(colors.yellow); print(msg); setFG(colors.white) end
local function printInfo(msg) setFG(colors.cyan);   print(msg); setFG(colors.white) end

-- Subcommands --------------------------------------------------------------

local function cmd_check()
    printInfo("Checking for updates ...")
    local repoURL = getCurrentRepo()
    print("  Repo: " .. repoURL)
    print("")
    local info, err = fetchUpdateInfo(repoURL)
    if not info then
        printErr("  Failed to fetch update info: " .. tostring(err))
        printErr("  Check your internet connection and the repo URL.")
        return 1
    end
    local curVer = getCurrentVersion()
    print("  Current version: " .. curVer)
    print("  Latest version:  " .. info.version)
    print("  Released:         " .. info.date)
    print("")
    local cmp = versionCompare(curVer, info.version)
    if cmp < 0 then
        printOK("  Update available!")
        print("")
        printWarn("  Run 'update install' to download and apply the update.")
        return 0
    elseif cmp == 0 then
        printOK("  System is up to date.")
        return 0
    else
        printWarn("  Your local version is NEWER than the repo. Dev build?")
        return 0
    end
end

local function cmd_install()
    local repoURL = getCurrentRepo()
    printInfo("Fetching update info ...")
    local info, err = fetchUpdateInfo(repoURL)
    if not info then
        printErr("Failed: " .. tostring(err))
        return 1
    end
    local curVer = getCurrentVersion()
    if versionCompare(curVer, info.version) >= 0 then
        printOK("System is already up to date (v" .. curVer .. ").")
        return 0
    end
    print("  Current: v" .. curVer)
    print("  Available: v" .. info.version)
    print("")
    printWarn("Files to update (" .. #info.files .. "):")
    for _, f in ipairs(info.files) do
        print("  - " .. f)
    end
    print("")
    -- Ask about backup
    term.setTextColor(colors.yellow)
    term.write("Create backup before updating? [Y/n] ")
    term.setTextColor(colors.white)
    local answer = read()
    answer = (answer or ""):lower()
    if answer ~= "n" and answer ~= "no" then
        -- Create backup directory with timestamp
        local ts = tostring(os.epoch and os.epoch("utc") or os.time())
        local backupDir = "/backup/archos-" .. ts
        if not fs.exists("/backup") then fs.makeDir("/backup") end
        if not fs.exists(backupDir) then fs.makeDir(backupDir) end
        printInfo("Creating backup at " .. backupDir .. " ...")
        -- Copy essential system dirs
        local function copyDir(src, dst)
            if not fs.exists(src) then return end
            if not fs.exists(dst) then fs.makeDir(dst) end
            for _, name in ipairs(fs.list(src)) do
                local s = src .. "/" .. name
                local d = dst .. "/" .. name
                if fs.isDir(s) then
                    copyDir(s, d)
                else
                    fs.copy(s, d)
                end
            end
        end
        for _, dir in ipairs({"kernel", "bin", "sbin", "lib", "bios", "bootloader", "de", "etc"}) do
            copyDir("/" .. dir, backupDir .. "/" .. dir)
        end
        -- Also copy startup.lua
        if fs.exists("/startup.lua") then
            fs.copy("/startup.lua", backupDir .. "/startup.lua")
        end
        printOK("Backup created at " .. backupDir)
        print("")
    end

    -- Create update pending file with the file list
    if not fs.exists("/tmp") then fs.makeDir("/tmp") end
    local pf = fs.open("/tmp/update.pending", "w")
    if pf then
        pf.write("repo=" .. repoURL .. "\n")
        pf.write("version=" .. info.version .. "\n")
        pf.write("files=\n")
        for _, f in ipairs(info.files) do
            pf.write(f .. "\n")
        end
        pf.close()
    end

    printOK("Update scheduled. Rebooting to apply ...")
    os.sleep(2)
    os.reboot()
    return 0
end

local function cmd_ver()
    local curVer = getCurrentVersion()
    print("Current version: " .. curVer)
    local repoURL = getCurrentRepo()
    print("Repo: " .. repoURL)
    return 0
end

local function cmd_wn()
    printInfo("Fetching What's New from repo ...")
    local repoURL = getCurrentRepo()
    local info, err = fetchUpdateInfo(repoURL)
    if not info then
        printErr("Failed: " .. tostring(err))
        return 1
    end
    print("")
    setFG(colors.lightBlue)
    print("What's New in v" .. info.version .. " (" .. info.date .. "):")
    setFG(colors.white)
    print("------------------------------------------")
    if info.whatsnew and info.whatsnew ~= "" then
        print(info.whatsnew)
    else
        print("(no notes available)")
    end
    return 0
end

local function cmd_repo(args)
    if not args or not args[1] or args[1] == "" then
        -- Show current
        local url = getCurrentRepo()
        print("Current repo URL: " .. url)
        print("")
        print("To change:")
        print("  update repo <url>     Switch to a custom repo (raw URL)")
        print("  update repo default   Use the official Tsundereplan/archos-cc repo")
        return 0
    end
    local newURL = args[1]
    if newURL:lower() == "default" then
        newURL = DEFAULT_RAW
        printOK("Switched to official repo: " .. newURL)
    else
        -- Make sure it ends with /
        if newURL:sub(-1) ~= "/" then newURL = newURL .. "/" end
        printOK("Switched to: " .. newURL)
    end
    saveCurrentRepo(newURL)
    return 0
end

-- Main ---------------------------------------------------------------------

local function main()
    local subcommand = arg and arg[1] or "check"
    local subArgs = {}
    if arg then
        for i = 2, #arg do table.insert(subArgs, arg[i]) end
    end

    if subcommand == "check" then
        return cmd_check()
    elseif subcommand == "install" then
        return cmd_install()
    elseif subcommand == "ver" then
        return cmd_ver()
    elseif subcommand == "wn" then
        return cmd_wn()
    elseif subcommand == "repo" then
        return cmd_repo(subArgs)
    else
        print("Usage: update [check|install|ver|wn|repo [url]]")
        print("")
        print("Commands:")
        print("  check            Check if an update is available (default)")
        print("  install          Install available update (asks for backup)")
        print("  ver              Show current and latest versions")
        print("  wn               Show What's New for the latest update")
        print("  repo             Show current repository URL")
        print("  repo <url>       Switch to a different repository")
        print("  repo default     Switch back to the official repo")
        return 1
    end
end

return main()
