--[[
    usr/bin/clock.lua  —  GUI Clock & Calendar
    =========================================
    A graphical clock application with:
      * Large ASCII art digital clock
      * Calendar view for current month
      * Date and day of week
]]

local function setColor(c)
    if c and term.isColor() then
        pcall(function() term.setTextColor(c) end)
    end
end

local function setBG(c)
    if c and term.isColor() then
        pcall(function() term.setBackgroundColor(c) end)
    end
end

-- Big digits 0-9 for digital clock display (5 rows tall, 5 cols wide)
local DIGITS = {
    ["0"] = {
        " ### ",
        "#   #",
        "#   #",
        "#   #",
        " ### ",
    },
    ["1"] = {
        "  #  ",
        " ##  ",
        "  #  ",
        "  #  ",
        " ### ",
    },
    ["2"] = {
        " ### ",
        "#   #",
        "  ## ",
        " #   ",
        "#####",
    },
    ["3"] = {
        " ### ",
        "#   #",
        "  ## ",
        "#   #",
        " ### ",
    },
    ["4"] = {
        "#   #",
        "#   #",
        "#####",
        "    #",
        "    #",
    },
    ["5"] = {
        "#####",
        "#    ",
        "#### ",
        "    #",
        "#### ",
    },
    ["6"] = {
        " ### ",
        "#    ",
        "#### ",
        "#   #",
        " ### ",
    },
    ["7"] = {
        "#####",
        "    #",
        "   # ",
        "  #  ",
        " #   ",
    },
    ["8"] = {
        " ### ",
        "#   #",
        " ### ",
        "#   #",
        " ### ",
    },
    ["9"] = {
        " ### ",
        "#   #",
        " ####",
        "    #",
        " ### ",
    },
    [":"] = {
        "     ",
        "  #  ",
        "     ",
        "  #  ",
        "     ",
    },
}

local function drawBigText(text, startX, startY, color)
    setColor(color)
    for row = 1, 5 do
        local line = ""
        for i = 1, #text do
            local ch = text:sub(i, i)
            local digit = DIGITS[ch]
            if digit then
                line = line .. digit[row] .. " "
            else
                line = line .. "      "
            end
        end
        term.setCursorPos(startX, startY + row - 1)
        term.write(line)
    end
    setColor(colors.white)
end

-- Get day of week (Zeller's congruence, simplified)
local function dayOfWeek(year, month, day)
    -- Use os.date which is available in CC:Tweaked
    return os.date("%A", os.time())
end

-- Get days in month
local function daysInMonth(month, year)
    local days = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
    if month == 2 then
        if (year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0 then
            return 29
        end
        return 28
    end
    return days[month]
end

-- Day of week for the 1st of month (1=Sunday, 7=Saturday)
local function firstDayOfMonth(year, month)
    -- Use os.time to get a timestamp for the 1st of the month
    -- CC:Tweaked's os.time uses real time
    local t = os.time()
    -- Just use a simple calculation based on os.date
    return tonumber(os.date("%w", os.time({year=year, month=month, day=1}))) + 1
end

local function drawCalendar(year, month, today)
    local days = {"Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"}
    local startX = 30
    local startY = 6

    setColor(colors.cyan)
    term.setCursorPos(startX, startY - 1)
    local monthNames = {"January", "February", "March", "April", "May", "June",
                       "July", "August", "September", "October", "November", "December"}
    term.write(monthNames[month] .. " " .. year)
    setColor(colors.white)

    -- Day headers
    setColor(colors.yellow)
    for i, day in ipairs(days) do
        term.setCursorPos(startX + (i - 1) * 3, startY)
        term.write(day)
    end
    setColor(colors.white)

    -- Days
    local first = firstDayOfMonth(year, month)
    if not first then first = 1 end
    local total = daysInMonth(month, year)
    local day = 1
    for row = 1, 6 do
        for col = 1, 7 do
            local pos = (row - 1) * 7 + col
            if pos >= first and day <= total then
                term.setCursorPos(startX + (col - 1) * 3, startY + row)
                if day == today then
                    setColor(colors.black)
                    setBG(colors.yellow)
                    term.write(string.format("%2d", day))
                    setBG(colors.black)
                    setColor(colors.white)
                else
                    setColor(colors.white)
                    term.write(string.format("%2d", day))
                end
            end
        end
        if day > total then break end
    end
end

local function main()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)

    while true do
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)

        -- Title
        setColor(colors.lightBlue)
        print("    ArchOS-CC Clock")
        print("    ===============")
        setColor(colors.white)
        print("")

        -- Get current time
        local timeStr = os.date("%H:%M")
        local dateStr = os.date("%Y-%m-%d")
        local dayName = os.date("%A")
        local monthStr = os.date("%m")
        local yearStr = os.date("%Y")
        local dayNum = tonumber(os.date("%d"))
        local monthNum = tonumber(monthStr)
        local yearNum = tonumber(yearStr)

        -- Draw big clock
        drawBigText(timeStr, 4, 5, colors.green)

        -- Date info
        setColor(colors.cyan)
        term.setCursorPos(4, 12)
        print("Date: " .. dateStr)
        term.setCursorPos(4, 13)
        print("Day:  " .. dayName)
        setColor(colors.white)

        -- Calendar
        drawCalendar(yearNum, monthNum, dayNum)

        -- Footer
        setColor(colors.yellow)
        local w, h = term.getSize()
        term.setCursorPos(1, h - 1)
        print("Press 'q' to quit, 'r' to refresh")
        setColor(colors.white)

        -- Wait for key or timer
        local timer = os.startTimer(30)
        local event = {os.pullEvent()}
        if event[1] == "key" then
            if event[2] == keys.q then break end
        elseif event[1] == "char" then
            if event[2] == "q" then break end
        end
    end

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    return 0
end

return main()
