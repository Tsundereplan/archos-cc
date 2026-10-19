-- /sbin/fsck.lua  —  File system check
-- Simple file system integrity checker (basic version)
local target = arg[1] or "/"

if term.isColor() then term.setTextColor(colors.cyan) end
print("fsck: checking " .. target)

local issues = 0
local checked = 0

-- Walk the tree and look for obvious problems
local function walk(path)
    if not fs.exists(path) then return end
    checked = checked + 1
    if fs.isDir(path) then
        local ok, items = pcall(fs.list, path)
        if not ok then
            print("  [ERROR] Cannot list: " .. path)
            issues = issues + 1
            return
        end
        for _, name in ipairs(items) do
            local child = path
            if path:sub(-1) ~= "/" then child = child .. "/" end
            child = child .. name
            walk(child)
        end
    else
        -- Try to open the file
        local f = fs.open(path, "r")
        if not f then
            print("  [WARN] Cannot read: " .. path)
            issues = issues + 1
        else
            f.close()
        end
    end
end

walk(target)

if term.isColor() then
    if issues == 0 then
        term.setTextColor(colors.green)
        print("fsck: " .. checked .. " files checked, no issues found")
    else
        term.setTextColor(colors.yellow)
        print("fsck: " .. checked .. " files checked, " .. issues .. " issues found")
    end
    term.setTextColor(colors.white)
end
os.exit(0)
