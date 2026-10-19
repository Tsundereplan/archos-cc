-- bin/date.lua  —  Print or format the system date and time
-- Usage:
--   date                       print current date/time
--   date -u                    print UTC date/time (same as local in CC:Tweaked)
--   date +"<format>"           print date using a strftime-style format
--   date --help                show this help

local args = {...}
if not args or #args == 0 then args = arg or {} end

-- -- Parse arguments ---------------------------------------------------------
local utc = false
local format = nil
local showHelp = false

local i = 1
while i <= #args do
    local a = args[i]
    if a == "--help" or a == "-h" then
        showHelp = true
        i = i + 1
    elseif a == "-u" or a == "--utc" or a == "--universal" then
        utc = true
        i = i + 1
    elseif a:sub(1, 1) == "+" then
        -- Format string starts with '+'; everything after is the format
        format = a:sub(2)
        i = i + 1
    elseif a == "-R" or a == "--rfc-email" then
        format = "%a, %d %b %Y %H:%M:%S %z"
        i = i + 1
    elseif a:sub(1, 2) == "--" then
        io.stderr:write("date: unrecognized option '" .. a .. "'\n")
        return 1
    else
        -- Allow format argument as a bare string starting with %
        format = a
        i = i + 1
    end
end

if showHelp then
    io.write("Usage: date [OPTION]... [+FORMAT]\n")
    io.write("Print the system date and time.\n")
    io.write("  -u, --utc, --universal   print UTC time (no-op in CC:Tweaked)\n")
    io.write("  +FORMAT                  strftime-style format string\n")
    return 0
end

-- -- Output ------------------------------------------------------------------
-- CC:Tweaked os.date() accepts the same format strings as Lua's os.date.
-- With no format it returns a date string like "Sat Jan  1 12:00:00 2000".
-- `-u` has no effect because CC:Tweaked's clock is already in real-world UTC.
if format then
    io.write(os.date(format) .. "\n")
else
    io.write(os.date("%a %b %d %H:%M:%S %Z %Y") .. "\n")
end

return 0
