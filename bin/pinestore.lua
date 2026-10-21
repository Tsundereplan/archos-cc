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
    -- install_command is like "wget run https://example.com/install.lua"
    -- Extract the URL
    local installURL = installCommand:match("https?://%S+")
    if not installURL then
        return nil, "could not extract URL from install_command: " .. installCommand
    end
    -- Fetch the install script
    local body = fetchURL(installURL)
    if not body then
        return nil, "failed to fetch install script from " .. installURL
    end
    -- Execute the install script (it returns lua code)
    local fn, err = load(body, "pinestore-install", "t", _G)
    if not fn then return nil, "compile error: " .. tostring(err) end
    return pcall(fn)
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

    c(colors.cyan, function() io.write("[pinestore] Installing '" .. appId .. "' ...\n") end)
    local ok, err = PineStore.install(appId)
    if ok then
        c(colors.green, function() print("[pinestore] Installed '" .. appId .. "' successfully.") end)
        return 0
    end
    c(colors.red, function()
        io.stderr:write("[pinestore] install failed: " .. tostring(err or "unknown error") .. "\n")
    end)
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
