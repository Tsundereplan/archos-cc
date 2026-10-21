--[[
    usr/bin/print.lua  —  Print files to a Printer peripheral
    ========================================================
    Sends text files to an attached Printer block.

    Usage:
        print <file>                  Print a text file
        print <file> --title "Title"  Print with title
        print --list                  List attached printers
        print --status               Show printer status (paper/ink)
]]

local args = arg or {...}

local function setColor(c)
    if c and term.isColor() then pcall(function() term.setTextColor(c) end) end
end

-- Find printers
local function findPrinters()
    local printers = {}
    local sides = {"top", "bottom", "left", "right", "front", "back"}
    for _, side in ipairs(sides) do
        if peripheral.isPresent(side) and peripheral.getType(side) == "printer" then
            table.insert(printers, side)
        end
    end
    if peripheral.getNames then
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "printer"
               and name ~= "top" and name ~= "bottom"
               and name ~= "left" and name ~= "right"
               and name ~= "front" and name ~= "back" then
                table.insert(printers, name)
            end
        end
    end
    return printers
end

if args[1] == "--list" then
    local printers = findPrinters()
    if #printers == 0 then
        print("No printers attached.")
        return 1
    end
    print("Attached printers:")
    for i, side in ipairs(printers) do
        local p = peripheral.wrap(side)
        local paper = p.getPaperLevel and p.getPaperLevel() or "?"
        local ink = p.getInkLevel and p.getInkLevel() or "?"
        print(string.format("  %d. %-10s  paper:%s  ink:%s", i, side, tostring(paper), tostring(ink)))
    end
    return 0
end

if args[1] == "--status" then
    local printers = findPrinters()
    if #printers == 0 then
        print("No printers attached.")
        return 1
    end
    for _, side in ipairs(printers) do
        local p = peripheral.wrap(side)
        print("Printer at " .. side .. ":")
        print("  Paper: " .. tostring(p.getPaperLevel and p.getPaperLevel() or "?"))
        print("  Ink:   " .. tostring(p.getInkLevel and p.getInkLevel() or "?"))
    end
    return 0
end

if #args == 0 or args[1] == "-h" or args[1] == "--help" then
    print("Usage: print <file> [options]")
    print("")
    print("Options:")
    print("  --title \"Title\"    Set page title")
    print("  --list              List attached printers")
    print("  --status            Show printer status")
    return 0
end

local filePath = args[1]
local title = nil
for i = 2, #args do
    if args[i] == "--title" and args[i+1] then
        title = args[i+1]
        break
    end
end

if not fs.exists(filePath) then
    io.stderr:write("print: file not found: " .. filePath .. "\n")
    return 1
end

-- Read file
local f = fs.open(filePath, "r")
if not f then
    io.stderr:write("print: cannot open " .. filePath .. "\n")
    return 1
end
local content = f.readAll()
f.close()

-- Find printer
local printers = findPrinters()
if #printers == 0 then
    io.stderr:write("print: no printers attached.\n")
    io.stderr:write("  Place a Printer block next to the computer.\n")
    return 1
end

local printer = peripheral.wrap(printers[1])
setColor(colors.cyan)
print("[print] Using printer at " .. printers[1])
setColor(colors.white)

-- Check paper and ink
local paper = printer.getPaperLevel and printer.getPaperLevel() or 0
local ink = printer.getInkLevel and printer.getInkLevel() or 0
if paper == 0 then
    setColor(colors.red)
    print("[print] ERROR: No paper in printer!")
    print("  Insert paper (right-click printer with Paper item)")
    setColor(colors.white)
    return 1
end
if ink == 0 then
    setColor(colors.red)
    print("[print] ERROR: No ink in printer!")
    print("  Insert ink sac (right-click printer with Ink Sac)")
    setColor(colors.white)
    return 1
end

-- Start page
if not printer.newPage() then
    setColor(colors.red)
    print("[print] ERROR: Cannot start new page (out of paper/ink?)")
    setColor(colors.white)
    return 1
end

-- Print title
if title then
    printer.setCursorPos(1, 1)
    printer.write(title)
    printer.setCursorPos(1, 3)
end

-- Print content
local pageW, pageH = printer.getPageSize and printer.getPageSize() or 25, 21
local lineNum = 1
local y = title and 3 or 1

for line in (content or ""):gmatch("[^\n]*") do
    if y > pageH - 1 then
        -- Page full, start new page
        printer.endPage()
        setColor(colors.gray)
        print("[print] Page " .. lineNum .. " printed. Starting new page...")
        setColor(colors.white)
        lineNum = lineNum + 1
        if not printer.newPage() then
            setColor(colors.red)
            print("[print] Out of paper after page " .. (lineNum - 1))
            setColor(colors.white)
            return 1
        end
        y = 1
    end
    printer.setCursorPos(1, y)
    -- Truncate to page width
    local printLine = line
    if #printLine > pageW then printLine = printLine:sub(1, pageW) end
    printer.write(printLine)
    y = y + 1
end

-- End page
printer.endPage()

setColor(colors.green)
print("[print] Done! Printed " .. lineNum .. " page(s).")
setColor(colors.white)
return 0
