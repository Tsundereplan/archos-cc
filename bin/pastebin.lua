-- bin/pastebin.lua  —  Download, upload, or run pastebin.com pastes
-- Usage:
--   pastebin get <pasteID> <dest>
--   pastebin put <file>
--   pastebin run <pasteID> [args...]

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

local function usage()
    print("Usage: pastebin <command> [args...]")
    print("")
    print("Commands:")
    print("  get <pasteID> <dest>   download a paste to <dest>")
    print("  put <file>              upload a file (not yet supported)")
    print("  run <pasteID> [args...] download and execute a paste")
    return 0
end

if #args == 0 then
    return usage()
end

local subcmd = args[1]

-- Build raw URL
local function pasteURL(id)
    -- Allow both raw IDs and full pastebin URLs
    id = id:gsub("^https?://pastebin%.com/", "")
    id = id:gsub("^raw/", "")
    id = id:gsub("^/", "")
    return "https://pastebin.com/raw/" .. id
end

-- Fetch the body of a paste
local function fetchPaste(id)
    if not Network or not Network.httpGet then
        return nil, "http not available"
    end
    local url = pasteURL(id)
    c(colors.cyan, function() io.write("[pastebin] Fetching " .. url .. " ...\n") end)
    local body, err = Network.httpGet(url)
    if not body then
        return nil, err or "request failed"
    end
    return body
end

-- pastebin get <pasteID> <dest>
if subcmd == "get" then
    local pasteID = args[2]
    local dest    = args[3]
    if not pasteID or not dest then
        io.stderr:write("pastebin get: usage: pastebin get <pasteID> <dest>\n")
        return 1
    end
    if FS then dest = FS.normalize(dest) end

    local body, err = fetchPaste(pasteID)
    if not body then
        c(colors.red, function()
            io.stderr:write("pastebin: failed to download: " .. tostring(err) .. "\n")
        end)
        return 1
    end

    c(colors.cyan, function() io.write("[pastebin] Saving to " .. dest .. "\n") end)
    local f
    if FS and FS.open then f = FS.open(dest, "w") else f = fs.open(dest, "w") end
    if not f then
        c(colors.red, function() io.stderr:write("pastebin: cannot open '" .. dest .. "' for writing\n") end)
        return 1
    end
    f.write(body)
    f.close()
    c(colors.green, function()
        print(string.format("[pastebin] Wrote %d bytes to %s", #body, dest))
    end)
    return 0

-- pastebin put <file>
elseif subcmd == "put" then
    local file = args[2]
    if not file then
        io.stderr:write("pastebin put: usage: pastebin put <file>\n")
        return 1
    end
    c(colors.yellow, function()
        io.stderr:write("pastebin: upload is not yet supported without a Pastebin API key.\n")
    end)
    io.stderr:write("pastebin: configure PASTEBIN_API_KEY in /etc/pastebin.conf to enable uploads.\n")
    return 1

-- pastebin run <pasteID> [args...]
elseif subcmd == "run" then
    local pasteID = args[2]
    if not pasteID then
        io.stderr:write("pastebin run: usage: pastebin run <pasteID> [args...]\n")
        return 1
    end
    local extraArgs = {}
    for k = 3, #args do table.insert(extraArgs, args[k]) end

    local body, err = fetchPaste(pasteID)
    if not body then
        c(colors.red, function()
            io.stderr:write("pastebin: failed to download: " .. tostring(err) .. "\n")
        end)
        return 1
    end

    c(colors.cyan, function() io.write("[pastebin] Executing ...\n") end)
    local fn, lerr = load(body, "pastebin:" .. pasteID, "t", _G)
    if not fn then
        c(colors.red, function()
            io.stderr:write("pastebin: compile error: " .. tostring(lerr) .. "\n")
        end)
        return 1
    end
    -- Save/restore arg table so the paste sees its args
    local savedArg = arg
    arg = { [0] = "pastebin:" .. pasteID, table.unpack(extraArgs) }
    local ok, rerr = pcall(fn, table.unpack(extraArgs))
    arg = savedArg
    if not ok then
        c(colors.red, function()
            io.stderr:write("pastebin: runtime error: " .. tostring(rerr) .. "\n")
        end)
        return 1
    end
    return 0

elseif subcmd == "-h" or subcmd == "--help" or subcmd == "help" then
    return usage()
else
    io.stderr:write("pastebin: unknown command '" .. subcmd .. "'\n")
    usage()
    return 1
end
