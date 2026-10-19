-- bin/wget.lua  —  Non-interactive network downloader
-- Usage: wget <URL> [DEST]

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

-- Human-readable size
local function humanSize(n)
    if not n then return "?" end
    if n < 1024 then return tostring(n) .. "B" end
    if n < 1024 * 1024 then return string.format("%.1fK", n / 1024) end
    return string.format("%.1fM", n / (1024 * 1024))
end

-- Extract a filename from a URL
local function filenameFromURL(url)
    -- Strip query string and fragment
    local path = url:gsub("^[^:]+://[^/]+/", "")
    path = path:gsub("%?.*$", ""):gsub("#.*$", "")
    -- Strip trailing slash
    path = path:gsub("/+$", "")
    -- Take last component
    local name = path:match("([^/]+)$") or path
    if name == "" then name = "index.html" end
    return name
end

-- Parse args
local url, dest
for _, a in ipairs(args) do
    if a == "-h" or a == "--help" then
        print("Usage: wget <URL> [DEST]")
        print("Download a file via HTTP.")
        print("If DEST is omitted, the file is saved to the current directory")
        print("using the basename of the URL.")
        return 0
    elseif not url then
        url = a
    elseif not dest then
        dest = a
    end
end

if not url then
    io.stderr:write("wget: missing URL\n")
    io.stderr:write("Usage: wget <URL> [DEST]\n")
    return 1
end

if not Network then
    io.stderr:write("wget: network subsystem unavailable\n")
    return 1
end

-- Determine destination
if not dest then
    local cwd = Kernel and Kernel.getCwd and Kernel.getCwd() or "/"
    local name = filenameFromURL(url)
    dest = (cwd:sub(-1) == "/" and cwd or cwd .. "/") .. name
end
if FS then dest = FS.normalize(dest) end

c(colors.cyan, function() io.write("[wget] Connecting to " .. url .. " ...\n") end)
c(colors.cyan, function() io.write("[wget] Saving to " .. dest .. "\n") end)

if not Network.online and Network.httpGet then
    -- httpGet works even when rednet is down; only the wrapper requires network.
    -- But check if http API exists at all
end

local body, err
if Network.httpGet then
    body, err = Network.httpGet(url)
else
    io.stderr:write("wget: http support not available\n")
    return 1
end

if not body then
    c(colors.red, function()
        io.stderr:write("wget: download failed: " .. tostring(err or "unknown error") .. "\n")
    end)
    return 1
end

-- Write to file
local f
if FS and FS.open then
    f = FS.open(dest, "w")
else
    f = fs.open(dest, "w")
end
if not f then
    c(colors.red, function()
        io.stderr:write("wget: cannot open '" .. dest .. "' for writing\n")
    end)
    return 1
end
f.write(body)
f.close()

local size = #body
c(colors.green, function()
    print(string.format("[wget] %s  (%d bytes, %s)", dest, size, humanSize(size)))
end)

return 0
