-- bin/dmesg.lua  —  Print or control the kernel boot log
-- Usage:
--   dmesg                    print the boot log (/var/log/boot.log)
--   dmesg --clear            truncate the boot log after reading
--   dmesg --help             show this help

local args = {...}
if not args or #args == 0 then args = arg or {} end

local LOG_PATH = "/var/log/boot.log"
local FS = _G.FS

-- -- Parse flags -------------------------------------------------------------
local clearFlag = false
for _, a in ipairs(args) do
    if a == "--clear" or a == "-C" then
        clearFlag = true
    elseif a == "--help" or a == "-h" then
        io.write("Usage: dmesg [--clear]\n")
        io.write("Print or clear the kernel boot log.\n")
        return 0
    end
end

-- -- Open the log file (use VFS.open so permission checks apply) -------------
local function openLog(mode)
    if FS and FS.open then return FS.open(LOG_PATH, mode) end
    return fs.open(LOG_PATH, mode)
end
local function exists(path)
    if FS and FS.exists then return FS.exists(path) end
    return fs.exists(path)
end

if not exists(LOG_PATH) then
    -- Empty boot log: not an error in dmesg semantics
    return 0
end

local f = openLog("r")
if not f then
    io.stderr:write("dmesg: cannot open " .. LOG_PATH .. ": permission denied\n")
    return 1
end

local content = f.readAll()
f.close()

if content and content ~= "" then
    -- Ensure a trailing newline for clean display
    if content:sub(-1) == "\n" then
        io.write(content)
    else
        io.write(content .. "\n")
    end
end

-- -- Optional --clear: truncate the log file ---------------------------------
if clearFlag then
    local w = openLog("w")
    if w then
        w.close()
    else
        io.stderr:write("dmesg: cannot clear " .. LOG_PATH ..
                        ": permission denied\n")
        return 1
    end
end

return 0
