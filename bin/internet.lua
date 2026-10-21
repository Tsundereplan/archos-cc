--[[
    bin/internet.lua  —  Internet connection checker & setup
    =======================================================
    Quickly checks if the computer has internet access (via HTTP API)
    and walks the user through enabling it if not.

    Usage:
        internet           Check connection
        internet enable    Show step-by-step enable instructions
        internet test      Run a connectivity test
]]

local function setColor(c)
    if c and term.isColor() then pcall(function() term.setTextColor(c) end) end
end

local function setBG(c)
    if c and term.isColor() then pcall(function() term.setBackgroundColor(c) end) end
end

local function resetColors()
    setBG(colors.black)
    setColor(colors.white)
end

local function banner()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    setColor(colors.lightBlue)
    print("    ArchOS-CC Internet Check")
    print("    ========================")
    setColor(colors.white)
    print("")
end

-- Check if HTTP API is available
local function checkHTTP()
    banner()
    setColor(colors.cyan)
    print("Step 1: Check HTTP API")
    setColor(colors.white)
    if http then
        setColor(colors.green)
        print("  [OK] http API is available")
        setColor(colors.white)
        return true
    else
        setColor(colors.red)
        print("  [FAIL] http API is NOT available")
        setColor(colors.white)
        print("")
        setColor(colors.yellow)
        print("  The HTTP API is disabled on this server.")
        print("  To enable:")
        print("    1. Stop the Minecraft server")
        print("    2. Open config/computercraft-server.toml")
        print("    3. Find the [http] section")
        print("    4. Set enabled = true:")
        print("")
        setColor(colors.white)
        print("       [http]")
        print("       enabled = true")
        print("")
        setColor(colors.yellow)
        print("    5. Also make sure your domain whitelist allows all sites:")
        print("       Add to [http]:")
        print("")
        setColor(colors.white)
        print("       [[http.rules]]")
        print('       host = "*"')
        print('       action = "allow"')
        print("")
        setColor(colors.yellow)
        print("    6. Restart the server")
        return false
    end
end

-- Check if we can actually reach the internet
local function checkConnectivity()
    print("")
    setColor(colors.cyan)
    print("Step 2: Test connectivity")
    setColor(colors.white)
    if not http then
        setColor(colors.red)
        print("  [SKIP] HTTP API not available")
        setColor(colors.white)
        return false
    end
    setColor(colors.gray)
    term.write("  Trying to reach example.com ... ")
    setColor(colors.white)

    local url = "https://example.com"
    http.request(url)
    local timer = os.startTimer(10)
    local hbTimer = os.startTimer(2)
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "http_success" and ev[2] == url then
            local handle = ev[3]
            if handle then
                local body = handle.readAll()
                handle.close()
                os.cancelTimer(timer)
                os.cancelTimer(hbTimer)
                -- Clear the dots
                local _, y = term.getCursorPos()
                term.setCursorPos(1, y)
                term.clearLine()
                setColor(colors.green)
                print("  [OK] Got response from example.com")
                setColor(colors.gray)
                print("       (response size: " .. #body .. " bytes)")
                setColor(colors.white)
                return true
            end
        elseif ev[1] == "http_failure" and ev[2] == url then
            os.cancelTimer(timer)
            os.cancelTimer(hbTimer)
            local _, y = term.getCursorPos()
            term.setCursorPos(1, y)
            term.clearLine()
            setColor(colors.red)
            print("  [FAIL] Request failed: " .. tostring(ev[3] or "no reason"))
            setColor(colors.white)
            return false
        elseif ev[1] == "timer" and ev[2] == timer then
            local _, y = term.getCursorPos()
            term.setCursorPos(1, y)
            term.clearLine()
            setColor(colors.red)
            print("  [FAIL] Timeout - no response in 10s")
            setColor(colors.white)
            return false
        elseif ev[1] == "timer" and ev[2] == hbTimer then
            term.write(".")
            hbTimer = os.startTimer(2)
        end
    end
end

-- Test GitHub specifically (since we use it for updates)
local function checkGitHub()
    print("")
    setColor(colors.cyan)
    print("Step 3: Test GitHub access")
    setColor(colors.white)
    if not http then
        setColor(colors.red)
        print("  [SKIP] HTTP API not available")
        setColor(colors.white)
        return false
    end
    setColor(colors.gray)
    term.write("  Trying github.com ... ")
    setColor(colors.white)
    local url = "https://github.com"
    http.request(url)
    local timer = os.startTimer(10)
    local hbTimer = os.startTimer(2)
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "http_success" and ev[2] == url then
            local handle = ev[3]
            if handle then handle.close() end
            os.cancelTimer(timer)
            os.cancelTimer(hbTimer)
            local _, y = term.getCursorPos()
            term.setCursorPos(1, y)
            term.clearLine()
            setColor(colors.green)
            print("  [OK] GitHub is reachable")
            setColor(colors.white)
            return true
        elseif ev[1] == "http_failure" and ev[2] == url then
            os.cancelTimer(timer)
            os.cancelTimer(hbTimer)
            local _, y = term.getCursorPos()
            term.setCursorPos(1, y)
            term.clearLine()
            setColor(colors.red)
            print("  [FAIL] GitHub request failed")
            setColor(colors.yellow)
            print("         ArchOS-CC updates use raw.githubusercontent.com")
            print("         Make sure both github.com AND raw.githubusercontent.com")
            print("         are allowed in your http.rules whitelist.")
            setColor(colors.white)
            return false
        elseif ev[1] == "timer" and ev[2] == timer then
            local _, y = term.getCursorPos()
            term.setCursorPos(1, y)
            term.clearLine()
            setColor(colors.red)
            print("  [FAIL] Timeout")
            setColor(colors.white)
            return false
        elseif ev[1] == "timer" and ev[2] == hbTimer then
            term.write(".")
            hbTimer = os.startTimer(2)
        end
    end
end

-- Check modems (for rednet, not for HTTP, but useful diagnostic)
local function checkModems()
    print("")
    setColor(colors.cyan)
    print("Step 4: Check attached modems (for rednet networking)")
    setColor(colors.white)
    local found = {}
    local sides = {"top", "bottom", "left", "right", "front", "back"}
    for _, side in ipairs(sides) do
        if peripheral.isPresent(side) then
            local ptype = peripheral.getType(side)
            if ptype == "modem" then
                local wrap = peripheral.wrap(side)
                local isWireless = false
                if wrap and wrap.isWireless then
                    local ok, res = pcall(wrap.isWireless)
                    if ok then isWireless = res end
                end
                table.insert(found, { side = side, wireless = isWireless })
            end
        end
    end
    -- Also via wired modem
    if peripheral.getNames then
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "modem"
               and name ~= "top" and name ~= "bottom"
               and name ~= "left" and name ~= "right"
               and name ~= "front" and name ~= "back" then
                local wrap = peripheral.wrap(name)
                local isWireless = false
                if wrap and wrap.isWireless then
                    local ok, res = pcall(wrap.isWireless)
                    if ok then isWireless = res end
                end
                table.insert(found, { side = name, wireless = isWireless })
            end
        end
    end
    if #found == 0 then
        setColor(colors.yellow)
        print("  [INFO] No modems attached")
        setColor(colors.white)
        print("  Note: modems are NOT required for HTTP/internet access.")
        print("        They're used for rednet (computer-to-computer chat).")
        print("        For web browsing, just need HTTP API enabled.")
        print("")
        print("  To attach a modem:")
        print("    1. Craft a Wireless Modem (ender pearl + redstone + stone)")
        print("       OR a Wired Modem (redstone + stone, no ender pearl)")
        print("    2. Place it adjacent to the Advanced Computer")
        print("       (top, bottom, left, right, front, or back side)")
        print("    3. For Wired Modem, also need Networking Cable to connect")
        print("       to other peripherals (monitors, disk drives, etc.)")
        print("    4. Right-click the modem to activate it (if it shows red dot,")
        print("       it's off; right-click turns it on with green dot)")
    else
        for _, m in ipairs(found) do
            setColor(colors.green)
            print("  [OK] Modem at " .. m.side .. " (" ..
                (m.wireless and "wireless" or "wired") .. ")")
            setColor(colors.white)
        end
    end
end

local function main(...)
    local args = arg or {...}
    if args[1] == "enable" then
        banner()
        setColor(colors.yellow)
        print("How to enable HTTP/internet on your Minecraft server:")
        print("")
        setColor(colors.white)
        print("1. STOP the Minecraft server (don't just reload - full restart)")
        print("")
        print("2. Open the ComputerCraft config file:")
        print("   Forge:  config/computercraft-server.toml")
        print("   Fabric: config/computercraft-server.toml")
        print("   (older versions: config/ComputerCraft.cfg)")
        print("")
        print("3. Find the [http] section and set:")
        print("")
        setColor(colors.cyan)
        print("   [http]")
        print("   enabled = true")
        print("")
        setColor(colors.white)
        print("4. To allow access to ALL websites, add this rule:")
        print("")
        setColor(colors.cyan)
        print("   [[http.rules]]")
        print('   host = "*"')
        print('   action = "allow"')
        print("")
        setColor(colors.white)
        print("   (Or restrict to specific domains for security:")
        print("")
        setColor(colors.cyan)
        print("   [[http.rules]]")
        print('   host = "raw.githubusercontent.com"')
        print('   action = "allow"')
        print("")
        print("   [[http.rules]]")
        print('   host = "github.com"')
        print('   action = "allow"')
        print("")
        print("   [[http.rules]]")
        print('   host = "lite.duckduckgo.com"')
        print('   action = "allow"')
        print("")
        print("   [[http.rules]]")
        print('   host = "*"')
        print('   action = "deny"')
        print("")
        setColor(colors.white)
        print("   ... etc)")
        print("")
        print("5. Start the Minecraft server.")
        print("")
        print("6. Run 'internet' again to test.")
        print("")
        return 0
    end

    if args[1] == "test" then
        banner()
        checkHTTP()
        checkConnectivity()
        checkGitHub()
        checkModems()
        print("")
        setColor(colors.lightBlue)
        print("==========================================")
        setColor(colors.white)
        return 0
    end

    -- Default: full check
    banner()
    local httpOk = checkHTTP()
    local connOk = false
    local ghOk = false
    if httpOk then
        connOk = checkConnectivity()
        ghOk = checkGitHub()
    end
    checkModems()
    print("")
    setColor(colors.lightBlue)
    print("==========================================")
    print("Summary:")
    if httpOk and connOk then
        setColor(colors.green)
        print("  Internet: WORKING")
        setColor(colors.white)
        if ghOk then
            setColor(colors.green)
            print("  GitHub:   REACHABLE (updates will work)")
            setColor(colors.white)
        else
            setColor(colors.yellow)
            print("  GitHub:   NOT REACHABLE (updates may fail)")
            setColor(colors.white)
        end
        print("")
        setColor(colors.cyan)
        print("  You can now use:")
        print("    webbrowser        Browse the web")
        print("    webbrowser <url>  Open a specific URL")
        print("    wget <url> [dest] Download a file")
        print("    update check      Check for ArchOS-CC updates")
        print("    git clone USER/REPO  Clone a GitHub repo")
        setColor(colors.white)
    else
        setColor(colors.red)
        print("  Internet: NOT WORKING")
        setColor(colors.white)
        print("")
        setColor(colors.yellow)
        print("  Run 'internet enable' for setup instructions.")
        setColor(colors.white)
    end
    return 0
end

return main()
