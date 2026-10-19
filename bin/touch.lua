-- bin/touch.lua  —  Update file timestamps or create empty files
local FS = _G.FS
local args = {...}
local targets = {}
local noCreate = false

for _, a in ipairs(args) do
    if a == "-c" or a == "--no-create" then noCreate = true
    elseif a == "--help" then
        print("Usage: touch [OPTION]... FILE...")
        print("Update access and modification times of each FILE to current time.")
        print("  -c, --no-create    do not create any files")
        return 0
    else
        table.insert(targets, a)
    end
end

if #targets == 0 then
    io.stderr:write("touch: missing file operand\n")
    return 1
end

local ret = 0
for _, t in ipairs(targets) do
    local path = t
    if FS then path = FS.normalize(path) end
    if fs.exists(path) then
        -- We can't update timestamps in CC:Tweaked, so this is a no-op
        -- In a real OS, this would touch the mtime
    else
        if not noCreate then
            local f = fs.open(path, "w")
            if not f then
                io.stderr:write("touch: cannot touch '" .. t .. "': Permission denied\n")
                ret = 1
            else
                f.close()
            end
        end
    end
end
return ret
