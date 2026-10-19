-- bin/df.lua  —  Report filesystem disk space usage
-- Usage: df [OPTIONS] [PATH...]
-- Options:
--   -h, --human   human-readable sizes (K, M, G)
--   --help        show help

local FS = _G.FS
local args = arg or {...}

-- -- Options -- --
local human = false
local targets = {}

local i = 1
while i <= #args do
    local a = args[i]
    if a == "--help" then
        print("Usage: df [OPTION]... [PATH]...")
        print("Show filesystem disk space usage.")
        print("  -h, --human   human-readable sizes")
        return 0
    elseif a:sub(1, 1) == "-" and #a > 1 then
        -- combined short opts
        for j = 2, #a do
            local c = a:sub(j, j)
            if c == "h" then human = true
            else
                io.stderr:write("df: invalid option -- '" .. c .. "'\n")
                return 1
            end
        end
    else
        table.insert(targets, a)
    end
    i = i + 1
end

-- -- Build list of mounts to display -- --
local mounts
if FS and FS.mounts then
    mounts = FS.mounts()
else
    -- Fallback: a single root mount
    mounts = { { path = "/", source = "/", type = "root", options = "rw" } }
end

-- If user supplied paths, filter to mounts containing those paths
if #targets > 0 then
    local filtered = {}
    for _, m in ipairs(mounts) do
        for _, t in ipairs(targets) do
            local norm = FS and FS.normalize(t) or t
            if norm:sub(1, #m.path) == m.path then
                table.insert(filtered, m)
                break
            end
        end
    end
    mounts = filtered
end

-- -- Helpers -- --
local function humanSize(b)
    if b == nil then return "-" end
    if b < 1024 then return string.format("%dB", b) end
    if b < 1024 * 1024 then return string.format("%.1fK", b / 1024) end
    if b < 1024 * 1024 * 1024 then return string.format("%.1fM", b / (1024 * 1024)) end
    return string.format("%.1fG", b / (1024 * 1024 * 1024))
end

local function fmtSize(b)
    if human then return humanSize(b) end
    return tostring(b or 0)
end

local function freeBytes(path)
    if FS and FS.getFreeSpace then
        return tonumber(FS.getFreeSpace(path)) or 0
    end
    if fs and fs.getFreeSpace then
        return tonumber(fs.getFreeSpace(FS and FS.resolve(path) or path)) or 0
    end
    return 0
end

-- Total disk size isn't directly exposed by CC:Tweaked; we estimate
-- by computing used space via walking and free via getFreeSpace.
local usedCache = {}
local function usedBytes(path)
    if usedCache[path] then return usedCache[path] end
    local total = 0
    if FS and FS.walk then
        local ok = pcall(function()
            FS.walk(path, function(p, isDir)
                if not isDir and FS.getSize then
                    total = total + (tonumber(FS.getSize(p)) or 0)
                end
            end)
        end)
        if not ok then total = 0 end
    end
    usedCache[path] = total
    return total
end

-- -- Header -- --
local function writeHeader()
    if term.isColor() then term.setTextColor(colors.lightGray) end
    print(string.format("%-20s %8s %8s %8s %5s  %-15s",
        "Filesystem", "Size", "Used", "Avail", "Use%", "Mounted on"))
    if term.isColor() then term.setTextColor(colors.white) end
end

writeHeader()

-- -- Rows -- --
for _, m in ipairs(mounts) do
    local free = freeBytes(m.path)
    local used = usedBytes(m.path)
    local total = used + free
    local pct
    if total == 0 then
        pct = "0%"
    else
        pct = string.format("%d%%", math.floor(used * 100 / total + 0.5))
    end
    -- Filesystem column: show the source/dev
    local fsName = m.source or m.path or "?"
    local mountedOn = m.path or "?"
    print(string.format("%-20s %8s %8s %8s %5s  %-15s",
        fsName, fmtSize(total), fmtSize(used), fmtSize(free), pct, mountedOn))
end

return 0
