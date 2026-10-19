-- bin/git.lua  —  Minimal GitHub client (raw.githubusercontent.com)
-- Usage:
--   git clone <user/repo> [dest]   Clone a repo's files (branch defaults to main)
--   git pull                       Pull updates from origin (.git/origin)
--   git status                     Show working-tree status (basic)
--   git push <file>                (not yet supported without an API token)

local Network = _G.Network
local Kernel  = _G.Kernel
local FS      = _G.FS
local args    = {...}

local hasColor = term.isColor and term.isColor()
local function c(col, fn)
    if hasColor then term.setTextColor(col) end
    fn()
    if hasColor then term.setTextColor(colors.white) end
end

local function join(pathA, pathB)
    if pathA == "" or pathA == "/" then return pathB end
    if pathA:sub(-1) == "/" then return pathA .. pathB end
    return pathA .. "/" .. pathB
end

-- Make sure parent dirs exist for a target file path
local function ensureParent(path)
    local parent = path:match("^(.*)/[^/]+$")
    if not parent or parent == "" then return end
    if FS then
        if not FS.exists(parent) then FS.makeDir(parent) end
    else
        if not fs.exists(parent) then fs.makeDir(parent) end
    end
end

-- Write a file via FS or native fs
local function writeFile(path, content)
    ensureParent(path)
    local f
    if FS and FS.open then f = FS.open(path, "w") else f = fs.open(path, "w") end
    if not f then return false end
    f.write(content)
    f.close()
    return true
end

-- Recursively clone a directory at `path` into the local `destRoot`
local function cloneTree(user, repo, branch, path, destRoot, stats)
    stats = stats or { files = 0, dirs = 0, bytes = 0 }
    if not Network or not Network.githubList then
        return stats, "network not available"
    end
    local entries, err = Network.githubList(user, repo, branch, path)
    if not entries then
        return stats, err or "githubList failed"
    end
    -- entries may be a Lua table array (from JSON) or our fallback list
    for _, entry in ipairs(entries) do
        local name = entry.name
        local etype = entry.type
        local subPath = (path == "" or path == nil) and name or (path .. "/" .. name)
        local localPath = join(destRoot, subPath)
        if etype == "dir" or etype == "directory" then
            if FS then
                if not FS.exists(localPath) then FS.makeDir(localPath) end
            else
                if not fs.exists(localPath) then fs.makeDir(localPath) end
            end
            stats.dirs = stats.dirs + 1
            c(colors.lightBlue, function() io.write("[git]   " .. subPath .. "/\n") end)
            cloneTree(user, repo, branch, subPath, destRoot, stats)
        else
            -- Download the file via raw URL
            local body
            if Network.fetchGitHubRaw then
                body = Network.fetchGitHubRaw(user, repo, branch, subPath)
            else
                local url = string.format(
                    "https://raw.githubusercontent.com/%s/%s/%s/%s",
                    user, repo, branch, subPath)
                body = Network.httpGet and Network.httpGet(url)
            end
            if body then
                if writeFile(localPath, body) then
                    stats.files = stats.files + 1
                    stats.bytes = stats.bytes + #body
                    c(colors.green, function() io.write("[git]   " .. subPath .. "\n") end)
                else
                    c(colors.red, function() io.stderr:write("[git] failed to write " .. localPath .. "\n") end)
                end
            else
                c(colors.red, function() io.stderr:write("[git] failed to fetch " .. subPath .. "\n") end)
            end
        end
    end
    return stats
end

-- git clone <user/repo> [dest]
local function doClone(spec, destArg)
    if not spec then
        io.stderr:write("git clone: missing repository (user/repo)\n")
        return 1
    end
    -- Accept user/repo, user/repo@branch, or full URL
    local user, repo, branch
    branch = "main"
    local trimmed = spec:gsub("^https?://github%.com/", "")
    trimmed = trimmed:gsub("%.git$", "")
    local at = trimmed:find("@")
    if at then
        branch = trimmed:sub(at + 1)
        trimmed = trimmed:sub(1, at - 1)
    end
    user, repo = trimmed:match("^([^/]+)/([^/]+)$")
    if not user or not repo then
        io.stderr:write("git clone: invalid repository spec '" .. spec .. "' (use user/repo)\n")
        return 1
    end

    local dest = destArg or repo
    if FS then dest = FS.normalize(dest) end

    if not Network or not Network.online then
        c(colors.red, function() io.stderr:write("git: network is offline\n") end)
        return 1
    end

    c(colors.cyan, function()
        io.write("[git] Cloning into '" .. dest .. "' (branch: " .. branch .. ") ...\n")
    end)

    -- Create dest dir
    if FS then
        if not FS.exists(dest) then FS.makeDir(dest) end
    else
        if not fs.exists(dest) then fs.makeDir(dest) end
    end

    -- Persist origin info for `git pull`
    local dotGit = dest .. (dest:sub(-1) == "/" and "" or "/") .. ".git"
    if FS then
        if not FS.exists(dotGit) then FS.makeDir(dotGit) end
    else
        if not fs.exists(dotGit) then fs.makeDir(dotGit) end
    end
    local of
    if FS and FS.open then of = FS.open(dotGit .. "/origin", "w") else of = fs.open(dotGit .. "/origin", "w") end
    if of then
        of.write("user=" .. user .. "\n")
        of.write("repo=" .. repo .. "\n")
        of.write("branch=" .. branch .. "\n")
        of.close()
    end

    local stats, err = cloneTree(user, repo, branch, "", dest, nil)
    if err and not stats.files and stats.dirs == 0 then
        c(colors.red, function() io.stderr:write("[git] clone failed: " .. tostring(err) .. "\n") end)
        return 1
    end
    c(colors.green, function()
        print(string.format("[git] Done. %d files, %d dirs, %d bytes.",
            stats.files, stats.dirs, stats.bytes))
    end)
    return 0
end

-- git pull  (reads .git/origin)
local function doPull()
    local dotGit = ".git"
    local originPath = dotGit .. "/origin"
    local exists
    if FS then exists = FS.exists(originPath) else exists = fs.exists(originPath) end
    if not exists then
        io.stderr:write("git pull: not a git repository (no .git/origin found)\n")
        return 1
    end
    local f
    if FS and FS.open then f = FS.open(originPath, "r") else f = fs.open(originPath, "r") end
    if not f then
        io.stderr:write("git pull: cannot read origin\n")
        return 1
    end
    local content = f.readAll()
    f.close()

    local user, repo, branch = "user", "repo", "main"
    for line in (content or ""):gmatch("[^\r\n]+") do
        local k, v = line:match("^([^=]+)=(.*)$")
        if k and v then
            k = k:gsub("^%s+", ""):gsub("%s+$", "")
            if k == "user" then user = v
            elseif k == "repo" then repo = v
            elseif k == "branch" then branch = v end
        end
    end

    c(colors.cyan, function()
        io.write("[git] Pulling from " .. user .. "/" .. repo .. " (" .. branch .. ") ...\n")
    end)
    if not Network or not Network.online then
        c(colors.red, function() io.stderr:write("git: network is offline\n") end)
        return 1
    end

    -- Pull into the current working directory
    local cwd = Kernel and Kernel.getCwd and Kernel.getCwd() or "/"
    local stats = cloneTree(user, repo, branch, "", cwd, nil)
    c(colors.green, function()
        print(string.format("[git] Updated %d files (%d bytes).", stats.files, stats.bytes))
    end)
    return 0
end

-- git status (very basic)
local function doStatus()
    c(colors.green, function() print("On branch main") end)
    c(colors.yellow, function() print("no changes detected") end)
    return 0
end

-- git push <file>
local function doPush(file)
    if not file then
        io.stderr:write("git push: missing file operand\n")
        return 1
    end
    c(colors.red, function()
        io.stderr:write("git push: push is not yet supported without a GitHub API token.\n")
    end)
    io.stderr:write("git push: configure GITHUB_TOKEN in /etc/git.conf to enable push.\n")
    return 1
end

local function usage()
    print("Usage: git <command> [args...]")
    print("")
    print("Commands:")
    print("  clone <user/repo> [dest]   Clone a GitHub repo to local dir")
    print("  pull                        Pull updates from origin")
    print("  status                      Show working-tree status")
    print("  push <file>                 (not yet supported)")
    return 0
end

local sub = args[1]
if not sub or sub == "-h" or sub == "--help" then
    return usage()
elseif sub == "clone" then
    return doClone(args[2], args[3])
elseif sub == "pull" then
    return doPull()
elseif sub == "status" then
    return doStatus()
elseif sub == "push" then
    return doPush(args[2])
else
    io.stderr:write("git: '" .. sub .. "' is not a git command. See 'git --help'.\n")
    return 1
end
