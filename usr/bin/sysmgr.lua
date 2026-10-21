--[[
    usr/bin/sysmgr.lua  —  System Manager (TUI)
    ===========================================
    A tabbed control panel for ArchOS-CC system administration.
    Tabs: Users / Network / Services / Packages / Hardware / Logs.

    Hotkeys:
      Tab / Left-Right arrows : switch tabs
      Up / Down               : navigate list
      a / d / r / s / x / e   : per-tab actions (see hotkey bar)
      q                       : quit
]]

local args = arg or {...}

-- colour helper (no-ops on monochrome)
local function setFG(c) if term.isColor() then term.setTextColor(c) end end
local function setBG(c) if term.isColor() then term.setBackgroundColor(c) end end
local function resetColors()
    if term.isColor() then
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
    end
end

-- Box-drawing characters (UTF-8 literals; modern CC:Tweaked supports them,
-- matching the convention already used by bin/tree.lua).
local BOX_TL = "+"  -- top-left
local BOX_TR = "+"  -- top-right
local BOX_BL = "+"  -- bottom-left
local BOX_BR = "+"  -- bottom-right
local BOX_H  = "="  -- horizontal
local BOX_V  = "|"  -- vertical

local function hline(x, y, w, left, mid, right)
    term.setCursorPos(x, y)
    term.write(left .. string.rep(mid, w - 2) .. right)
end
local function box(x, y, w, h)
    -- double-line border
    hline(x, y,         w, BOX_TL, BOX_H, BOX_TR) -- top
    hline(x, y + h - 1, w, BOX_BL, BOX_H, BOX_BR) -- bottom
    for i = 2, h - 1 do
        term.setCursorPos(x, y + i - 1)
        term.write(BOX_V)                          -- left
        term.setCursorPos(x + w - 1, y + i - 1)
        term.write(BOX_V)                          -- right
    end
end
local function writeAt(x, y, s)
    term.setCursorPos(x, y)
    term.write(s)
end

-- State
local state = {
    tab = 1,
    tabs = { "Users", "Network", "Services", "Packages", "Hardware", "Logs" },
    selected = 1,
    scroll = 1,
    message = "",
    msgTime = 0,
}

-- Message flash
local function msg(s)
    state.message = s
    state.msgTime = os.clock()
end

-- Cached data per tab (refresh on demand)
local cache = {
    users = {},
    units = {},
    pkgs = {},
    periphs = {},
    logLines = {},
}

local function refreshUsers()
    cache.users = {}
    if _G.Users and _G.Users.listUsers then
        for _, name in ipairs(_G.Users.listUsers()) do
            local u = _G.Users.getUser(name) or {}
            table.insert(cache.users, {
                name = name,
                uid = u.uid or 0,
                gid = u.gid or 0,
                home = u.home or "?",
                shell = u.shell or "?",
            })
        end
    end
    table.sort(cache.users, function(a, b) return (a.uid or 0) < (b.uid or 0) end)
end

local function refreshNetwork()
    -- nothing to cache, read live
end

local function refreshUnits()
    cache.units = {}
    if _G.Systemd and _G.Systemd.listUnits then
        for _, u in ipairs(_G.Systemd.listUnits()) do
            local enabled = _G.Systemd.enabled and _G.Systemd.enabled[u.name] or false
            table.insert(cache.units, {
                name = u.name,
                state = u.state or "unknown",
                enabled = enabled,
            })
        end
    end
end

local function refreshPkgs()
    cache.pkgs = {}
    if _G.Pacman and _G.Pacman.listInstalled then
        for _, p in ipairs(_G.Pacman.listInstalled()) do
            table.insert(cache.pkgs, {
                name = p.name,
                version = p.version or "?",
                desc = p.description or "",
            })
        end
    end
    table.sort(cache.pkgs, function(a, b) return a.name < b.name end)
end

local function refreshPeriphs()
    cache.periphs = {}
    if _G.BIOS and _G.BIOS.scanPeripherals then
        _G.BIOS.scanPeripherals()
        local sides = {"top","bottom","left","right","front","back"}
        for _, s in ipairs(sides) do
            local ptype = (_G.BIOS.hw and _G.BIOS.hw.peripherals and _G.BIOS.hw.peripherals[s]) or "(none)"
            table.insert(cache.periphs, { side = s, type = ptype })
        end
    else
        -- Fallback to direct peripheral scan
        local sides = {"top","bottom","left","right","front","back"}
        for _, s in ipairs(sides) do
            local ptype = "(none)"
            if peripheral.isPresent and peripheral.isPresent(s) then
                ptype = peripheral.getType(s) or "unknown"
            end
            table.insert(cache.periphs, { side = s, type = ptype })
        end
    end
end

local function refreshLogs()
    cache.logLines = {}
    local path = "/var/log/boot.log"
    local f = fs.open(path, "r")
    if not f then
        cache.logLines = { "(no boot.log found)" }
        return
    end
    local content = f.readAll()
    f.close()
    for line in content:gmatch("[^\r\n]*") do
        if line ~= "" then table.insert(cache.logLines, line) end
    end
end

local function refreshTab()
    local t = state.tabs[state.tab]
    if t == "Users"     then refreshUsers()
    elseif t == "Services"  then refreshUnits()
    elseif t == "Packages"  then refreshPkgs()
    elseif t == "Hardware"  then refreshPeriphs()
    elseif t == "Logs"      then refreshLogs()
    end
    state.selected = 1
    state.scroll = 1
end

-- Prompt for input on the bottom line
local function prompt(label)
    local _, h = term.getSize()
    term.setCursorPos(1, h)
    term.clearLine()
    setFG(colors.yellow)
    term.write(label)
    setFG(colors.white)
    local v = read()
    return v
end

---------------------------------------------------------------- render ---

local function renderTopBar(w)
    -- title bar
    setBG(colors.blue)
    setFG(colors.white)
    term.setCursorPos(1, 1)
    local title = " ArchOS-CC System Manager "
    title = title .. string.rep(" ", math.max(0, w - #title))
    term.write(title:sub(1, w))
    resetColors()

    -- tab strip
    setBG(colors.black)
    setFG(colors.lightGray)
    term.setCursorPos(1, 2)
    local tabsStr = ""
    for i, name in ipairs(state.tabs) do
        if i == state.tab then
            tabsStr = tabsStr .. " [" .. name .. "] "
        else
            tabsStr = tabsStr .. "  " .. name .. "  "
        end
    end
    tabsStr = tabsStr .. string.rep(" ", math.max(0, w - #tabsStr))
    term.write(tabsStr:sub(1, w))
    setFG(colors.gray)
    term.setCursorPos(1, 3)
    term.write(string.rep("-", w))
    resetColors()
end

local function renderPanel(x, y, w, h, title)
    box(x, y, w, h)
    if title and #title > 0 then
        setFG(colors.cyan)
        writeAt(x + 2, y, " " .. title .. " ")
        resetColors()
    end
end

local function renderList(items, x, y, w, h, selIdx, scroll)
    scroll = scroll or 1
    local endIdx = math.min(#items, scroll + h - 1)
    for i = scroll, endIdx do
        local row = y + (i - scroll)
        term.setCursorPos(x, row)
        if i == selIdx then
            setBG(colors.blue)
            setFG(colors.white)
        else
            setBG(colors.black)
            setFG(colors.lightGray)
        end
        local line = items[i] or ""
        line = line:sub(1, w - 2)
        term.write(" " .. line .. string.rep(" ", math.max(0, w - 2 - #line)))
        resetColors()
    end
    -- clear unused rows
    for r = (endIdx - scroll + 2), h do
        term.setCursorPos(x, y + r - 1)
        term.clearLine()
        term.setCursorPos(x, y + r - 1)
        term.write(string.rep(" ", w - 2))
    end
end

local function renderUsers(w, h)
    local bodyTop = 4
    local bodyH = h - 5
    renderPanel(1, bodyTop, w, bodyH, "Users")
    local listW = math.max(20, math.floor(w * 0.6))
    local infoX = listW + 2
    local infoW = w - listW - 2
    -- list
    local items = {}
    for _, u in ipairs(cache.users) do
        table.insert(items, string.format("%-12s uid=%-4d gid=%-4d %s",
            u.name, u.uid, u.gid, u.home))
    end
    if #items == 0 then items = { "(no users)" } end
    renderList(items, 2, bodyTop + 1, w - 2, bodyH - 2, state.selected, state.scroll)

    -- detail panel
    if infoW > 8 and cache.users[state.selected] then
        local u = cache.users[state.selected]
        renderPanel(infoX, bodyTop + 1, infoW, bodyH - 2, "Detail")
        local lines = {
            "Name  : " .. u.name,
            "UID   : " .. u.uid,
            "GID   : " .. u.gid,
            "Home  : " .. u.home,
            "Shell : " .. u.shell,
            "",
            "a=add  d=delete",
        }
        for i, ln in ipairs(lines) do
            if i <= bodyH - 4 then
                setFG(colors.lightGray)
                writeAt(infoX + 1, bodyTop + 1 + i, ln:sub(1, infoW - 2))
                resetColors()
            end
        end
    end
end

local function renderNetwork(w, h)
    local bodyTop = 4
    renderPanel(1, bodyTop, w, h - 5, "Network")
    local N = _G.Network or {}
    local row = bodyTop + 2
    local function kv(label, val, color)
        setFG(colors.yellow); writeAt(3, row, label)
        setFG(color or colors.white); writeAt(3 + #label + 1, row, tostring(val))
        resetColors()
        row = row + 1
    end
    kv("Status:", N.online and "ONLINE" or "OFFLINE", N.online and colors.green or colors.red)
    kv("Hostname:", N.hostname or "(unset)")
    kv("Channel:", N.channel or "?")
    kv("Protocol:", N.protocol or "?")

    -- modem list
    row = row + 1
    setFG(colors.cyan); writeAt(3, row, "Modems:"); resetColors()
    row = row + 1
    if N.modems and #N.modems > 0 then
        for _, m in ipairs(N.modems) do
            local side = m.side or "?"
            local wl = m.isWireless and "(wireless)" or "(wired)"
            setFG(colors.lightGray)
            writeAt(5, row, string.format("%-8s %s", side, wl))
            resetColors()
            row = row + 1
        end
    else
        setFG(colors.gray); writeAt(5, row, "(no modems attached)"); resetColors()
        row = row + 1
    end

    -- hosts (if any)
    row = row + 1
    setFG(colors.cyan); writeAt(3, row, "Known hosts:"); resetColors()
    row = row + 1
    if N.hosts then
        local count = 0
        for host, id in pairs(N.hosts) do
            setFG(colors.lightGray)
            writeAt(5, row, string.format("%-16s -> id %s", host, tostring(id)))
            resetColors()
            row = row + 1
            count = count + 1
            if row > h - 3 then break end
        end
        if count == 0 then
            setFG(colors.gray); writeAt(5, row, "(none registered)"); resetColors()
        end
    else
        setFG(colors.gray); writeAt(5, row, "(none registered)"); resetColors()
    end
end

local function renderServices(w, h)
    local bodyTop = 4
    renderPanel(1, bodyTop, w, h - 5, "Services")
    local items = {}
    for _, u in ipairs(cache.units) do
        local stateStr = u.state or "?"
        local enStr = u.enabled and "[enabled]" or "[disabled]"
        table.insert(items, string.format("%-20s %-12s %s", u.name, stateStr, enStr))
    end
    if #items == 0 then items = { "(no service units)" } end
    renderList(items, 2, bodyTop + 1, w - 2, h - 7, state.selected, state.scroll)

    -- hint
    local sel = cache.units[state.selected]
    if sel then
        setFG(colors.gray)
        writeAt(2, h - 2, "Selected: " .. sel.name .. "  s=start x=stop e=enable d=disable")
        resetColors()
    end
end

local function renderPackages(w, h)
    local bodyTop = 4
    renderPanel(1, bodyTop, w, h - 5, "Installed Packages")
    local items = {}
    for _, p in ipairs(cache.pkgs) do
        table.insert(items, string.format("%-20s %-12s %s", p.name, p.version, p.desc))
    end
    if #items == 0 then items = { "(no packages installed)" } end
    renderList(items, 2, bodyTop + 1, w - 2, h - 7, state.selected, state.scroll)

    local sel = cache.pkgs[state.selected]
    if sel then
        setFG(colors.gray)
        writeAt(2, h - 2, "Selected: " .. sel.name .. "-" .. sel.version .. "  u=upgrade-all r=remove s=sync")
        resetColors()
    end
end

local function renderHardware(w, h)
    local bodyTop = 4
    renderPanel(1, bodyTop, w, h - 5, "Hardware / Peripherals")
    local items = {}
    for _, p in ipairs(cache.periphs) do
        table.insert(items, string.format("%-8s -> %s", p.side, p.type))
    end
    renderList(items, 2, bodyTop + 1, w - 2, h - 7, state.selected, state.scroll)

    -- BIOS hw summary
    local hw = _G.BIOS and _G.BIOS.hw or {}
    setFG(colors.gray)
    writeAt(2, h - 2, string.format("Computer: %s  ID:%s  Adv:%s  Turtle:%s  Pocket:%s  (r=rescan)",
        tostring(hw.computerType), tostring(hw.computerID),
        tostring(hw.advanced), tostring(hw.isTurtle), tostring(hw.isPocket)))
    resetColors()
end

local function renderLogs(w, h)
    local bodyTop = 4
    renderPanel(1, bodyTop, w, h - 5, "/var/log/boot.log  (c=clear)")
    -- show last N lines
    local visible = h - 7
    local lines = cache.logLines or {}
    local startIdx = math.max(1, #lines - visible + 1)
    for i = startIdx, #lines do
        local line = lines[i] or ""
        local row = bodyTop + 1 + (i - startIdx)
        setFG(colors.lightGray)
        writeAt(2, row, line:sub(1, w - 3))
        resetColors()
    end
end

local function renderFooter(w, h)
    setBG(colors.lightGray)
    setFG(colors.black)
    term.setCursorPos(1, h)
    local hints = {
        "Tab=switch  Up/Dn=navigate  ",
        "a=add  d=del  r=refresh  s=sync/start  x=stop  e=enable  q=quit",
    }
    local bar = hints[1] .. hints[2]
    if state.message ~= "" and (os.clock() - state.msgTime) < 2.5 then
        bar = state.message
    end
    bar = bar .. string.rep(" ", math.max(0, w - #bar))
    term.write(bar:sub(1, w))
    resetColors()
end

local function render()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()
    renderTopBar(w)
    local t = state.tabs[state.tab]
    if t == "Users"     then renderUsers(w, h)
    elseif t == "Network"   then renderNetwork(w, h)
    elseif t == "Services"   then renderServices(w, h)
    elseif t == "Packages"   then renderPackages(w, h)
    elseif t == "Hardware"   then renderHardware(w, h)
    elseif t == "Logs"       then renderLogs(w, h)
    end
    renderFooter(w, h)
end

---------------------------------------------------------------- actions ---

local function tabUsersAction(c)
    if c == "a" then
        if _G.Kernel and _G.Kernel.getuid and _G.Kernel.getuid() ~= 0 then
            msg("Only root can add users")
            return
        end
        local name = prompt("Add user - name: ")
        if not name or name == "" then return end
        if not name:match("^[%w_%-]+$") then msg("Invalid name"); return end
        local pw = prompt("Password (blank for none): ")
        local opts = {}
        if pw and pw ~= "" then opts.password = pw end
        local ok, err = _G.Users.addUser(name, opts)
        if ok then msg("Added user " .. name); refreshUsers()
        else msg("Error: " .. tostring(err)) end
    elseif c == "d" then
        local u = cache.users[state.selected]
        if not u then return end
        if u.name == "root" then msg("Cannot delete root"); return end
        if _G.Kernel and _G.Kernel.getuid and _G.Kernel.getuid() ~= 0 then
            msg("Only root can delete users")
            return
        end
        local ok, err = _G.Users.delUser(u.name)
        if ok then msg("Deleted " .. u.name); refreshUsers()
        else msg("Error: " .. tostring(err)) end
    end
end

local function tabNetworkAction(c)
    if c == "h" then
        local name = prompt("New hostname: ")
        if not name or name == "" then return end
        if not name:match("^[%w%-%._]+$") then msg("Invalid hostname"); return end
        if _G.Network then
            _G.Network.hostname = name
            if _G.Network.saveConfig then _G.Network.saveConfig() end
            msg("Hostname set to " .. name)
        end
    elseif c == "r" then
        if _G.Network and _G.Network.discoverModems then _G.Network.discoverModems() end
        msg("Network refreshed")
    end
end

local function tabServicesAction(c)
    local u = cache.units[state.selected]
    if not u then return end
    if c == "s" then
        local ok, err = _G.Systemd.start(u.name)
        msg(ok and ("Started " .. u.name) or ("Error: " .. tostring(err)))
        refreshUnits()
    elseif c == "x" then
        local ok, err = _G.Systemd.stop(u.name)
        msg(ok and ("Stopped " .. u.name) or ("Error: " .. tostring(err)))
        refreshUnits()
    elseif c == "e" then
        _G.Systemd.enable(u.name)
        msg("Enabled " .. u.name); refreshUnits()
    elseif c == "d" then
        _G.Systemd.disable(u.name)
        msg("Disabled " .. u.name); refreshUnits()
    end
end

local function tabPackagesAction(c)
    if c == "u" then
        msg("Upgrading all packages...")
        render()
        if _G.Pacman and _G.Pacman.upgrade then
            local n = _G.Pacman.upgrade() or 0
            msg("Upgraded " .. tostring(n) .. " package(s)")
        end
        refreshPkgs()
    elseif c == "r" then
        local p = cache.pkgs[state.selected]
        if not p then return end
        if _G.Pacman and _G.Pacman.remove then
            local ok, err = _G.Pacman.remove(p.name)
            msg(ok and ("Removed " .. p.name) or ("Error: " .. tostring(err)))
            refreshPkgs()
        end
    elseif c == "s" then
        msg("Syncing package DB...")
        render()
        if _G.Pacman and _G.Pacman.sync then
            local ok, err = _G.Pacman.sync()
            msg(ok and "Sync complete" or ("Sync error: " .. tostring(err)))
        end
        refreshPkgs()
    end
end

local function tabHardwareAction(c)
    if c == "r" then
        refreshPeriphs()
        msg("Hardware rescanned")
    end
end

local function tabLogsAction(c)
    if c == "c" then
        local f = fs.open("/var/log/boot.log", "w")
        if f then f.close() end
        refreshLogs()
        msg("boot.log cleared")
    end
end

local function handleAction(c)
    local t = state.tabs[state.tab]
    if t == "Users"     then tabUsersAction(c)
    elseif t == "Network"   then tabNetworkAction(c)
    elseif t == "Services"  then tabServicesAction(c)
    elseif t == "Packages"  then tabPackagesAction(c)
    elseif t == "Hardware"  then tabHardwareAction(c)
    elseif t == "Logs"      then tabLogsAction(c)
    end
end

local function listSize()
    local t = state.tabs[state.tab]
    if t == "Users"     then return #cache.users
    elseif t == "Services"  then return #cache.units
    elseif t == "Packages"  then return #cache.pkgs
    elseif t == "Hardware"  then return #cache.periphs
    else return 0 end
end

---------------------------------------------------------------- main ---

local function main()
    -- initial data
    refreshTab()

    -- auto-refresh timer (10s)
    local autoTimer = os.startTimer(10)

    while true do
        render()
        local event = { os.pullEvent() }
        local ev = event[1]

        if ev == "timer" and event[2] == autoTimer then
            autoTimer = os.startTimer(10)
            -- silent refresh of current tab's data
            local t = state.tabs[state.tab]
            if t == "Users"     then refreshUsers()
            elseif t == "Services"  then refreshUnits()
            elseif t == "Packages"  then refreshPkgs()
            elseif t == "Logs"      then refreshLogs()
            end
        elseif ev == "key" then
            local key = event[2]
            if key == keys.tab or key == keys.right then
                state.tab = state.tab % #state.tabs + 1
                refreshTab()
            elseif key == keys.left then
                state.tab = (state.tab == 1) and #state.tabs or (state.tab - 1)
                refreshTab()
            elseif key == keys.up then
                state.selected = math.max(1, state.selected - 1)
            elseif key == keys.down then
                state.selected = math.min(math.max(1, listSize()), state.selected + 1)
            elseif key == keys.q then
                break
            end
        elseif ev == "char" then
            local c = event[2]:lower()
            if c == "q" then break
            elseif c == "r" then
                refreshTab()
                msg("Refreshed")
            else
                handleAction(c)
            end
        end
    end

    resetColors()
    term.clear()
    term.setCursorPos(1, 1)
    return 0
end

return main()
