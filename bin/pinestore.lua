-- bin/pinestore.lua  —  pinestore.cc client (CC:Tweaked app store)
-- Usage:
--   pinestore search <query>
--   pinestore install <appId>
--   pinestore list
--   pinestore info <appId>

local Network = _G.Network
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

if not Network then
    io.stderr:write("pinestore: network subsystem unavailable\n")
    return 1
end

-- Normalize an app entry from the API response. The API may return a Lua table
-- (when textutils.unserializeJSON was used) or a raw string.
local function normalizeApp(entry)
    if type(entry) == "table" then
        return {
            id          = entry.id or entry.appId or entry.slug or "?",
            name        = entry.name or entry.title or entry.appName or "?",
            description = entry.description or entry.desc or "",
            author      = entry.author or entry.developer or "?",
            version     = entry.version or "?",
            downloads   = entry.downloads or entry.installs or "?",
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
    if not Network.online then
        c(colors.red, function() io.stderr:write("pinestore: network is offline\n") end)
        return 1
    end
    if not Network.pinestoreSearch then
        io.stderr:write("pinestore: search not implemented in Network library\n")
        return 1
    end

    c(colors.cyan, function() io.write("[pinestore] Searching for '" .. query .. "' ...\n") end)
    local results = Network.pinestoreSearch(query)
    if not results then
        c(colors.yellow, function() print("[pinestore] No results (or request failed).") end)
        return 1
    end

    -- Normalize: results may be a table of apps, or a single app, or raw text
    local apps = {}
    if type(results) == "table" then
        if results[1] then
            for _, e in ipairs(results) do
                local a = normalizeApp(e)
                if a then table.insert(apps, a) end
            end
        elseif results.name or results.id then
            local a = normalizeApp(results)
            if a then table.insert(apps, a) end
        end
    elseif type(results) == "string" then
        -- Fallback: just print the raw response
        print(results)
        return 0
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
    if not Network.online then
        c(colors.red, function() io.stderr:write("pinestore: network is offline\n") end)
        return 1
    end
    if not Network.pinestoreInstall then
        io.stderr:write("pinestore: install not implemented in Network library\n")
        return 1
    end

    c(colors.cyan, function() io.write("[pinestore] Installing '" .. appId .. "' ...\n") end)
    local ok, err = Network.pinestoreInstall(appId)
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
    if not Network.online then
        c(colors.red, function() io.stderr:write("pinestore: network is offline\n") end)
        return 1
    end
    if not Network.pinestoreSearch then
        io.stderr:write("pinestore: search not implemented in Network library\n")
        return 1
    end

    c(colors.cyan, function() io.write("[pinestore] Fetching info for '" .. appId .. "' ...\n") end)
    local results = Network.pinestoreSearch(appId)
    if not results then
        c(colors.yellow, function() print("[pinestore] No info found (or request failed).") end)
        return 1
    end

    local app = nil
    if type(results) == "table" then
        if results[1] then
            for _, e in ipairs(results) do
                local a = normalizeApp(e)
                if a and (tostring(a.id) == appId or tostring(a.name) == appId) then
                    app = a; break
                end
            end
            if not app then app = normalizeApp(results[1]) end
        else
            app = normalizeApp(results)
        end
    end

    if not app then
        c(colors.yellow, function() print("[pinestore] No info available for '" .. appId .. "'.") end)
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
