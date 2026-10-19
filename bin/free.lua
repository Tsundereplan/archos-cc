-- bin/free.lua  —  Display memory and disk usage
-- Usage: free [-h|--human] [-b|-k|-m]
-- CC:Tweaked doesn't expose real RAM totals, so:
--   * "used"  = current Lua heap (collectgarbage count) in KB
--   * "free"  = free space on the root filesystem (_G.FS.getFreeSpace("/"))
--   * "total" = used + free (best-effort aggregate)

local FS = _G.FS
local args = arg or {...}

-- -- Options -- --
local unit = "k"     -- b=bytes, k=KiB, m=MiB
local human = false
local i = 1
while i <= #args do
    local a = args[i]
    if a == "-h" or a == "--human" then human = true
    elseif a == "-b" or a == "--bytes"  then unit = "b"
    elseif a == "-k" or a == "--kibi"   then unit = "k"
    elseif a == "-m" or a == "--mebi"   then unit = "m"
    elseif a == "--help" then
        print("Usage: free [OPTION]")
        print("  -h, --human   human-readable units")
        print("  -b            bytes")
        print("  -k            KiB (default)")
        print("  -m            MiB")
        return 0
    end
    i = i + 1
end

-- -- Gather numbers -- --
-- Free space on the root mount (in bytes)
local freeBytes = 0
if FS and FS.getFreeSpace then
    freeBytes = tonumber(FS.getFreeSpace("/")) or 0
elseif fs and fs.getFreeSpace then
    freeBytes = tonumber(fs.getFreeSpace("/")) or 0
end

-- Lua heap usage (collectgarbage returns KB)
local usedKb = collectgarbage("count") or 0
local usedBytes = usedKb * 1024

local totalBytes = freeBytes + usedBytes

-- -- Formatting -- --
local function humanSize(b)
    if b < 1024 then return string.format("%dB", b) end
    if b < 1024 * 1024 then return string.format("%.1fKiB", b / 1024) end
    if b < 1024 * 1024 * 1024 then return string.format("%.1fMiB", b / (1024 * 1024)) end
    return string.format("%.1fGiB", b / (1024 * 1024 * 1024))
end

local function fmtNum(b)
    if human then return humanSize(b) end
    if unit == "b" then return tostring(math.floor(b + 0.5)) end
    if unit == "m" then return string.format("%.0f", b / (1024 * 1024)) end
    -- default KiB
    return string.format("%.0f", b / 1024)
end

-- -- Header (colored if available) -- --
local function headerCell(s)
    if term.isColor() then term.setTextColor(colors.lightGray) end
    term.write(s)
    if term.isColor() then term.setTextColor(colors.white) end
end

-- Column widths
local w = 14

-- Print header
io.write(string.format("%-8s", ""))
headerCell(string.format("%" .. w .. "s", "total"))
io.write("  ")
headerCell(string.format("%" .. w .. "s", "used"))
io.write("  ")
headerCell(string.format("%" .. w .. "s", "free"))
print()

-- Print Mem row
io.write(string.format("%-8s", "Mem:"))
io.write(string.format("%" .. w .. "s  ", fmtNum(totalBytes)))
io.write(string.format("%" .. w .. "s  ", fmtNum(usedBytes)))
io.write(string.format("%" .. w .. "s",   fmtNum(freeBytes)))
print()

-- Swap row (no real swap in CC; report zeros)
io.write(string.format("%-8s", "Swap:"))
io.write(string.format("%" .. w .. "s  ", "0"))
io.write(string.format("%" .. w .. "s  ", "0"))
io.write(string.format("%" .. w .. "s",   "0"))
print()

return 0
