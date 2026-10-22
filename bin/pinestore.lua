-- bin/pinestore.lua  —  pinestore.cc client (CC:Tweaked app store)
-- Usage:
--   pinestore search <query>
--   pinestore install <appId>
--   pinestore list
--   pinestore info <appId>

local args    = {...}

local hasColor = term.isColor and term.isColor()
local function c(col, fn)
    if hasColor then term.setTextColor(col) end
    fn()
    if hasColor then term.setTextColor(colors.white) end
end

local function usage()
    print("Usage: pinestore <command> [args...]")
    print("")
    print("Commands:")
    print("  search <query>   search the pinestore.cc app store")
    print("  install <appId>  install an app by its ID")
    print("  list             list installed pinestore apps")
    print("  info <appId>     show info about an app")
    return 0
end

if #args == 0 or args[1] == "-h" or args[1] == "--help" then
    return usage()
end

local sub = args[1]

-- Async HTTP fetch with timeout (used for pinestore.cc API).
-- We don't rely on _G.Network because it tracks modem/rednet state,
-- not HTTP. Pinestore only needs HTTP.
local function fetchURL(url, timeoutSec)
    timeoutSec = timeoutSec or 15
    if not http then return nil, "HTTP API not enabled" end
    http.request(url)
    local timer = os.startTimer(timeoutSec)
    while true do
        local ev = {os.pullEvent()}
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

-- URL-encode a string (for query parameters)
local function urlEncode(s)
    s = tostring(s or "")
    local result = ""
    for i = 1, #s do
        local ch = s:sub(i, i)
        if ch:match("[%w%-_%.~]") then
            result = result .. ch
        else
            result = result .. string.format("%%%02X", string.byte(ch))
        end
    end
    return result
end

-- pinestore.cc API client
-- API docs: https://pinestore.cc/documentation
-- Endpoints:
--   GET /api/projects/search?q=<query>    - search projects
--   GET /api/project/<id>                  - get project info
--   POST /api/log/download                - report install (optional)
local PineStore = {}

function PineStore.search(query)
    if not http then return nil, "HTTP API not enabled" end
    local url = "https://pinestore.cc/api/projects/search?q=" .. urlEncode(query)
    local body = fetchURL(url)
    if not body then return nil end
    if textutils and textutils.unserializeJSON then
        local ok, result = pcall(textutils.unserializeJSON, body)
        if ok then return result end
    end
    return body
end

function PineStore.info(appId)
    if not http then return nil, "HTTP API not enabled" end
    local url = "https://pinestore.cc/api/project/" .. urlEncode(appId)
    local body = fetchURL(url)
    if not body then return nil end
    if textutils and textutils.unserializeJSON then
        local ok, result = pcall(textutils.unserializeJSON, body)
        if ok then return result end
    end
    return body
end

function PineStore.install(appId)
    if not http then return nil, "HTTP API not enabled" end
    -- First, get the project info to find install_command
    local info = PineStore.info(appId)
    if not info or type(info) ~= "table" then
        return nil, "could not fetch project info for ID " .. tostring(appId)
    end
    -- API response format: { success=true, project={...} }
    local project = info.project or info
    if not project then
        return nil, "no project info in API response"
    end
    local installCommand = project.install_command
    if not installCommand or installCommand == "" then
        return nil, "project has no install_command"
    end

    -- install_command can be:
    --   "wget run https://example.com/install.lua"
    --   "pastebin run yR1dxgcE"
    -- Handle both formats.

    local body = nil

    -- Try 1: extract URL starting with http
    local installURL = installCommand:match("https?://%S+")
    if installURL then
        body = fetchURL(installURL)
    end

    -- Try 2: pastebin format "pastebin run <code>"
    if not body then
        local pasteCode = installCommand:match("pastebin%s+run%s+(%S+)")
        if pasteCode then
            body = fetchURL("https://pastebin.com/raw/" .. pasteCode)
        end
    end

    -- Try 3: pastebin format "pastebin get <code> <dest>"
    if not body then
        local pasteCode = installCommand:match("pastebin%s+get%s+(%S+)")
        if pasteCode then
            body = fetchURL("https://pastebin.com/raw/" .. pasteCode)
        end
    end

    if not body then
        return nil, "could not extract URL from install_command: " .. installCommand
    end

    -- Execute the install script (it returns lua code)
    local fn, err = load(body, "pinestore-install", "t", _G)
    if not fn then return nil, "compile error: " .. tostring(err) end

    -- Record file list before install
    local beforeFiles = {}
    local function scanFiles(path, list)
        if not fs.exists(path) then return end
        if fs.isDir(path) then
            for _, name in ipairs(fs.list(path)) do
                scanFiles(path .. "/" .. name, list)
            end
        else
            table.insert(list, path)
        end
    end
    -- Only scan /programs and / (top-level)
    if fs.exists("/programs") then scanFiles("/programs", beforeFiles) end

    local ok, runErr = pcall(fn)

    -- Check if any new files were created
    local afterFiles = {}
    if fs.exists("/programs") then scanFiles("/programs", afterFiles) end

    local newFiles = 0
    for _, f in ipairs(afterFiles) do
        local found = false
        for _, old in ipairs(beforeFiles) do
            if old == f then found = true; break end
        end
        if not found then newFiles = newFiles + 1 end
    end

    if not ok then
        return nil, "install script error: " .. tostring(runErr)
    end

    -- If no new files were created, the install probably failed silently
    -- (e.g. "Out of space" printed but no Lua error thrown)
    if newFiles == 0 then
        -- Check if install script wrote to /disk (floppy disk)
        local diskFiles = 0
        local sides = {"top","bottom","left","right","front","back"}
        for _, side in ipairs(sides) do
            if peripheral.isPresent(side) and peripheral.getType(side) == "drive" then
                local drive = peripheral.wrap(side)
                if drive and drive.hasDisk then
                    local ok2, has = pcall(drive.hasDisk)
                    if ok2 and has then
                        local mp = nil
                        if drive.getMountPath then
                            local ok3, p = pcall(drive.getMountPath)
                            if ok3 and p then mp = p end
                        end
                        if not mp then
                            for i = 0, 5 do
                                local p = i == 0 and "/disk" or "/disk" .. (i + 1)
                                if fs.exists(p) then mp = p; break end
                            end
                        end
                        if mp then
                            scanFiles(mp, {})
                            -- Can't easily compare, just count
                            diskFiles = diskFiles + 1
                        end
                    end
                end
            end
        end
        if diskFiles == 0 then
            return nil, "install completed but no files were created (out of disk space?)"
        end
    end

    return true
end

-- Normalize an app entry from the API response.
-- Pinestore.cc API returns projects with fields:
--   id, name, owner_name, description_short, description,
--   install_command, downloads, downloads_recent, views, tags
local function normalizeApp(entry)
    if type(entry) == "table" then
        return {
            id          = entry.id or entry.appId or entry.slug or "?",
            name        = entry.name or entry.title or entry.appName or "?",
            description = entry.description_short or entry.description or entry.desc or "",
            author      = entry.owner_name or entry.author or entry.developer or "?",
            version     = entry.version or "?",
            downloads   = entry.downloads or entry.installs or "?",
            install_command = entry.install_command,
        }
    end
    return nil
end

-- pinestore search <query>
if sub == "search" then
    local query = args[2]
    if not query then
        io.stderr:write("pinestore search: missing query\n")
        return 1
    end
    if not http then
        c(colors.red, function() io.stderr:write("pinestore: HTTP API not enabled on this server\n") end)
        io.stderr:write("  Run 'internet enable' for setup instructions.\n")
        return 1
    end

    c(colors.cyan, function() io.write("[pinestore] Searching for '" .. query .. "' ...\n") end)
    local results = PineStore.search(query)
    if not results then
        c(colors.yellow, function() print("[pinestore] No results (or request failed).") end)
        print("  Possible causes:")
        print("    - pinestore.cc is down or unreachable")
        print("    - HTTP API whitelist blocks pinestore.cc")
        print("    - Server has no internet connection")
        print("")
        print("  Run 'internet' to diagnose.")
        return 1
    end

    -- API response: { success=true, projects=[{...}, ...] }
    -- Extract the projects array
    local projects
    if type(results) == "table" then
        if results.projects and type(results.projects) == "table" then
            projects = results.projects
        elseif results[1] then
            -- Already an array of projects
            projects = results
        elseif results.name or results.id then
            -- Single project
            projects = { results }
        end
    elseif type(results) == "string" then
        -- Fallback: just print the raw response
        print(results)
        return 0
    end

    if not projects or #projects == 0 then
        c(colors.yellow, function() print("[pinestore] No matching apps found for '" .. query .. "'.") end)
        print("  Try a different search term.")
        return 0
    end

    -- Normalize each project
    local apps = {}
    for _, e in ipairs(projects) do
        local a = normalizeApp(e)
        if a then table.insert(apps, a) end
    end

    if #apps == 0 then
        c(colors.yellow, function() print("[pinestore] No matching apps found.") end)
        return 0
    end

    -- Header
    print(string.format("  %-20s %-20s %-12s %s",
        "ID", "NAME", "VERSION", "AUTHOR"))
    print(string.rep("-", 78))
    for _, a in ipairs(apps) do
        c(colors.green, function()
            print(string.format("  %-20s %-20s %-12s %s",
                tostring(a.id):sub(1, 20),
                tostring(a.name):sub(1, 20),
                tostring(a.version):sub(1, 12),
                tostring(a.author)))
        end)
        if a.description and a.description ~= "" then
            c(colors.gray, function()
                print(string.format("    %s", tostring(a.description):sub(1, 70)))
            end)
        end
    end
    return 0

-- pinestore install <appId>
elseif sub == "install" then
    local appId = args[2]
    if not appId then
        io.stderr:write("pinestore install: missing appId\n")
        return 1
    end
    if not http then
        c(colors.red, function() io.stderr:write("pinestore: HTTP API not enabled\n") end)
        return 1
    end

    -- Check available disk space BEFORE attempting install
    local freeSpace = fs.getFreeSpace("/")
    c(colors.gray, function() print("[pinestore] Free disk space: " .. tostring(freeSpace) .. " bytes") end)

    -- Find attached disk drive with disk
    local diskPath = nil
    local diskSide = nil
    local sides = {"top","bottom","left","right","front","back"}
    for _, side in ipairs(sides) do
        if peripheral.isPresent(side) and peripheral.getType(side) == "drive" then
            local drive = peripheral.wrap(side)
            if drive and drive.hasDisk then
                local ok, has = pcall(drive.hasDisk)
                if ok and has then
                    -- Find mount path
                    local mp = nil
                    if drive.getMountPath then
                        local ok2, p = pcall(drive.getMountPath)
                        if ok2 and p then mp = p end
                    end
                    if not mp and drive.getDiskID then
                        local ok2, id = pcall(drive.getDiskID)
                        if ok2 and id ~= nil then
                            mp = id == 0 and "/disk" or "/disk" .. (id + 1)
                        end
                    end
                    if not mp then
                        for i = 0, 10 do
                            local p = i == 0 and "/disk" or "/disk" .. (i + 1)
                            if fs.exists(p) then mp = p; break end
                        end
                    end
                    if mp then
                        diskPath = mp
                        diskSide = side
                        break
                    end
                end
            end
        end
    end

    -- If disk space is low and we have a disk, redirect install there
    if freeSpace and freeSpace < 100000 and diskPath then
        c(colors.yellow, function()
            print("[pinestore] Low disk space! Installing to floppy disk at " .. diskPath)
        end)
        -- Change CWD to disk path so install script writes there
        local oldCwd = _G.Kernel and _G.Kernel.getCwd() or "/"
        if _G.Kernel then _G.Kernel.setCwd(diskPath) end
        -- Also temporarily remap fs.open to write to disk
        -- The install script usually writes to relative paths, so
        -- changing CWD should be enough.
        c(colors.cyan, function() io.write("[pinestore] Installing '" .. appId .. "' to " .. diskPath .. " ...\n") end)
        local ok, err = PineStore.install(appId)
        -- Restore CWD
        if _G.Kernel then _G.Kernel.setCwd(oldCwd) end
        if ok then
            c(colors.green, function() print("[pinestore] Installed '" .. appId .. "' to " .. diskPath) end)
            -- Add to apps.conf on local disk so it shows in GUI
            local f = fs.open("/etc/apps.conf", "a")
            if f then
                f.write((project and project.name or appId) .. "|" .. diskPath .. "/" .. (project and project.name or appId) .. ".lua|?|lightBlue\n")
                f.close()
            end
            return 0
        end
        c(colors.red, function()
            io.stderr:write("[pinestore] install failed: " .. tostring(err or "unknown error") .. "\n")
        end)
        return 1
    end

    c(colors.cyan, function() io.write("[pinestore] Installing '" .. appId .. "' ...\n") end)
    local ok, err = PineStore.install(appId)
    if ok then
        c(colors.green, function() print("[pinestore] Installed '" .. appId .. "' successfully.") end)
        -- Try to add to apps.conf
        local info = PineStore.info(appId)
        if info and info.project then
            local name = info.project.name or appId
            local installPath = "/" .. name:lower():gsub("%s", "_")
            local f = fs.open("/etc/apps.conf", "a")
            if f then
                f.write(name .. "|" .. installPath .. "/" .. name .. ".lua|?|lightBlue\n")
                f.close()
            end
        end
        return 0
    end
    c(colors.red, function()
        io.stderr:write("[pinestore] install failed: " .. tostring(err or "unknown error") .. "\n")
    end)
    -- If out of space, suggest disk
    if tostring(err):lower():find("space") then
        c(colors.yellow, function()
            print("[pinestore] Out of disk space!")
            if diskPath then
                print("  Re-run: pinestore install " .. appId)
                print("  (will auto-install to floppy disk at " .. diskPath .. ")")
            else
                print("  Insert a floppy disk and try again.")
                print("  Or increase computer_space_limit in computercraft-server.toml")
            end
        end)
    end
    return 1

-- pinestore list
elseif sub == "list" then
    c(colors.cyan, function()
        print("Installed pinestore apps are tracked via the package manager.")
    end)
    print("Use 'pacman -Q' to list all installed packages.")
    return 0

-- pinestore info <appId>
elseif sub == "info" then
    local appId = args[2]
    if not appId then
        io.stderr:write("pinestore info: missing appId\n")
        return 1
    end
    if not http then
        c(colors.red, function() io.stderr:write("pinestore: HTTP API not enabled\n") end)
        return 1
    end

    c(colors.cyan, function() io.write("[pinestore] Fetching info for '" .. appId .. "' ...\n") end)
    local results = PineStore.info(appId)
    if not results then
        c(colors.yellow, function() print("[pinestore] No info found (or request failed).") end)
        return 1
    end

    -- API response: { success=true, project={...} }
    local project
    if type(results) == "table" then
        if results.project then
            project = results.project
        elseif results.id or results.name then
            project = results
        end
    end

    local app = project and normalizeApp(project)

    if not app then
        c(colors.yellow, function() print("[pinestore] No info available for '" .. appId .. "'.") end)
        if type(results) == "string" then
            print("Raw response:")
            print(results:sub(1, 500))
        end
        return 1
    end

    print(string.format("  ID:          %s", app.id))
    print(string.format("  Name:        %s", app.name))
    print(string.format("  Version:     %s", app.version))
    print(string.format("  Author:      %s", app.author))
    print(string.format("  Downloads:   %s", tostring(app.downloads)))
    if app.description and app.description ~= "" then
        print(string.format("  Description: %s", app.description))
    end
    return 0

else
    io.stderr:write("pinestore: unknown command '" .. sub .. "'\n")
    usage()
    return 1
end
