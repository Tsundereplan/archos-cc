--[[
    usr/bin/settings.lua  —  Settings app (TUI)
    ===========================================
    Categorized ArchOS-CC settings viewer/editor.

    Layout: categories on the left, options on the right.

    Categories:
      System    - hostname, timezone, locale, default DE
      Network   - enable/disable, hostname, channel
      Boot     - boot delay, default boot entry, splash, boot menu
      Display  - colorscheme, font size
      Users    - current user info
      Security - PnP, debug log, root password change

    Hotkeys:
      Up/Dn   : navigate categories
      Tab     : move focus to options panel
      Enter   : edit highlighted option
      s       : save all changes to /etc/bios.conf
      q       : quit (prompts to save if dirty)
]]

local args = arg or {...}

-- Colour helpers
local function setFG(c) if term.isColor() then term.setTextColor(c) end end
local function setBG(c) if term.isColor() then term.setBackgroundColor(c) end end
local function resetColors()
    if term.isColor() then
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
    end
end

-- Box-drawing characters
local BOX_TL, BOX_TR, BOX_BL, BOX_BR = "+", "+", "+", "+"
local BOX_H,  BOX_V                   = "=", "|"

local function box(x, y, w, h)
    term.setCursorPos(x, y);         term.write(BOX_TL .. string.rep(BOX_H, w - 2) .. BOX_TR)
    term.setCursorPos(x, y + h - 1); term.write(BOX_BL .. string.rep(BOX_H, w - 2) .. BOX_BR)
    for i = 2, h - 1 do
        term.setCursorPos(x,         y + i - 1); term.write(BOX_V)
        term.setCursorPos(x + w - 1, y + i - 1); term.write(BOX_V)
    end
end
local function writeAt(x, y, s)
    term.setCursorPos(x, y)
    term.write(s)
end

-- Local working copy of BIOS config; we mutate this and persist on save.
local function getConfig()
    if _G.BIOS and _G.BIOS.config then return _G.BIOS.config end
    return {
        bootDelay       = 2,
        defaultBoot     = "archos",
        enableSplash    = true,
        enableBootMenu  = true,
        enablePnP       = true,
        enableNetwork   = true,
        enableDebugLog  = true,
        fontSize        = "normal",
        colorscheme     = "arch",
    }
end

-- Extra "soft" settings not stored in BIOS.config (kept in /etc/* files).
local softSettings = {
    hostname = "archos-cc",
    timezone = "UTC",
    locale   = "en_US",
    defaultDE = "sh",
    channel  = 1,
    rootPwChanged = false,
}

local function loadSoftSettings()
    -- hostname from Network
    if _G.Network and _G.Network.hostname then
        softSettings.hostname = _G.Network.hostname
    end
    if _G.Network and _G.Network.channel then
        softSettings.channel = _G.Network.channel
    end
    -- read /etc/locale.conf if exists
    if fs.exists("/etc/locale.conf") then
        local f = fs.open("/etc/locale.conf", "r")
        if f then
            for line in f.readLine do
                local k, v = line:match("^([%w_]+)%s*=%s*(.*)$")
                if k and v then
                    if k == "LANG"   then softSettings.locale   = v end
                    if k == "TZ"     then softSettings.timezone = v end
                    if k == "DE"     then softSettings.defaultDE = v end
                end
            end
            f.close()
        end
    end
end

local function saveSoftSettings()
    -- hostname
    if _G.Network then
        _G.Network.hostname = softSettings.hostname
        _G.Network.channel  = softSettings.channel
        if _G.Network.saveConfig then _G.Network.saveConfig() end
    end
    -- locale.conf
    if not fs.exists("/etc") then fs.makeDir("/etc") end
    local f = fs.open("/etc/locale.conf", "w")
    if f then
        f.write("LANG=" .. softSettings.locale .. "\n")
        f.write("TZ="   .. softSettings.timezone .. "\n")
        f.write("DE="   .. softSettings.defaultDE .. "\n")
        f.close()
    end
end

-- Build the option list per category. Each option is:
--   { key, label, getValue, setValue, kind, choices }
local categories = {
    "System", "Network", "Boot", "Display", "Users", "Security",
}

local function optionsFor(cat, cfg)
    if cat == "System" then
        return {
            { label = "Hostname",    kind = "string", get = function() return softSettings.hostname end,
              set  = function(v) softSettings.hostname = v end },
            { label = "Timezone",     kind = "string", get = function() return softSettings.timezone end,
              set  = function(v) softSettings.timezone = v end },
            { label = "Locale",       kind = "string", get = function() return softSettings.locale end,
              set  = function(v) softSettings.locale = v end },
            { label = "Default DE",  kind = "string", get = function() return softSettings.defaultDE end,
              set  = function(v) softSettings.defaultDE = v end },
        }
    elseif cat == "Network" then
        return {
            { label = "Enable network", kind = "bool",
              get = function() return cfg.enableNetwork end,
              set = function(v) cfg.enableNetwork = v end },
            { label = "Hostname",       kind = "string",
              get = function() return softSettings.hostname end,
              set  = function(v) softSettings.hostname = v end },
            { label = "Channel",        kind = "number",
              get = function() return softSettings.channel end,
              set  = function(v) softSettings.channel = v end },
        }
    elseif cat == "Boot" then
        return {
            { label = "Boot delay (s)",    kind = "number",
              get = function() return cfg.bootDelay end,
              set = function(v) cfg.bootDelay = v end },
            { label = "Default boot entry", kind = "string",
              get = function() return cfg.defaultBoot end,
              set = function(v) cfg.defaultBoot = v end },
            { label = "Splash screen",    kind = "bool",
              get = function() return cfg.enableSplash end,
              set = function(v) cfg.enableSplash = v end },
            { label = "Boot menu",        kind = "bool",
              get = function() return cfg.enableBootMenu end,
              set = function(v) cfg.enableBootMenu = v end },
        }
    elseif cat == "Display" then
        return {
            { label = "Colorscheme", kind = "choice",
              choices = {"arch","forest","ocean","sunset","dark"},
              get = function() return cfg.colorscheme end,
              set = function(v) cfg.colorscheme = v end },
            { label = "Font size",    kind = "choice",
              choices = {"normal","small"},
              get = function() return cfg.fontSize end,
              set = function(v) cfg.fontSize = v end },
        }
    elseif cat == "Users" then
        local uid = (_G.Kernel and _G.Kernel.getuid) and _G.Kernel.getuid() or 0
        local user = (_G.Kernel and _G.Kernel.getuser) and _G.Kernel.getuser() or "root"
        local home = (_G.Kernel and _G.Kernel.getEnv) and _G.Kernel.getEnv("HOME") or "/root"
        return {
            { label = "Current user", kind = "ro", get = function() return user end },
            { label = "UID",         kind = "ro", get = function() return tostring(uid) end },
            { label = "Home dir",    kind = "ro", get = function() return home end },
            { label = "Hostname",    kind = "ro", get = function() return softSettings.hostname end },
        }
    elseif cat == "Security" then
        return {
            { label = "Plug and Play",  kind = "bool",
              get = function() return cfg.enablePnP end,
              set = function(v) cfg.enablePnP = v end },
            { label = "Debug log",      kind = "bool",
              get = function() return cfg.enableDebugLog end,
              set = function(v) cfg.enableDebugLog = v end },
            { label = "Change root password", kind = "action",
              get = function() return "(press Enter)" end,
              set = function()
                  if _G.Kernel and _G.Kernel.getuid and _G.Kernel.getuid() ~= 0 then
                      return false, "only root can change root password"
                  end
                  return "prompt"
              end },
        }
    end
    return {}
end

---------------------------------------------------------------- state ---

local state = {
    cfg = getConfig(),
    catIdx = 1,
    optIdx = 1,
    focus = "cat",       -- "cat" or "opt"
    dirty = false,
    message = "",
    msgTime = 0,
    optScroll = 1,
}

local function msg(s)
    state.message = s
    state.msgTime = os.clock()
end

local function readInput(label, default, kind)
    local _, h = term.getSize()
    term.setCursorPos(1, h)
    term.clearLine()
    setFG(colors.yellow); term.write(label .. ": ")
    setFG(colors.white)
    local v = read(nil, nil, nil, default)
    return v
end

local function readChoice(label, choices, current)
    -- simple horizontal cycling for choice
    local idx = 1
    for i, c in ipairs(choices) do
        if c == current then idx = i break end
    end
    idx = (idx % #choices) + 1
    return choices[idx]
end

local function editOption(opt)
    local kind = opt.kind
    if kind == "ro" then
        msg("Read-only")
        return
    elseif kind == "bool" then
        opt.set(not opt.get())
        state.dirty = true
        msg(opt.label .. " = " .. tostring(opt.get()))
    elseif kind == "string" then
        local v = readInput(opt.label, opt.get())
        if v and v ~= "" then
            opt.set(v)
            state.dirty = true
            msg(opt.label .. " = " .. v)
        end
    elseif kind == "number" then
        local v = readInput(opt.label .. " (number)", tostring(opt.get()))
        local n = tonumber(v)
        if n then
            opt.set(n)
            state.dirty = true
            msg(opt.label .. " = " .. n)
        else
            msg("Invalid number")
        end
    elseif kind == "choice" then
        local v = readChoice(opt.label, opt.choices, opt.get())
        opt.set(v)
        state.dirty = true
        msg(opt.label .. " = " .. v)
    elseif kind == "action" then
        local r, err = opt.set()
        if r == "prompt" then
            -- change root password
            local pw1 = readInput("New root password")
            if not pw1 or pw1 == "" then msg("Password not changed"); return end
            local pw2 = readInput("Confirm password")
            if pw1 ~= pw2 then msg("Passwords do not match"); return end
            if _G.Users and _G.Users.shadow then
                _G.Users.shadow = _G.Users.shadow or {}
                _G.Users.shadow["root"] = _G.Users.hashPassword(pw1)
                if _G.Users.save then _G.Users.save() end
                softSettings.rootPwChanged = true
                state.dirty = true
                msg("Root password updated")
            else
                msg("Users API unavailable")
            end
        elseif r == false then
            msg(err or "Action failed")
        end
    end
end

---------------------------------------------------------------- render ---

local function renderCategories(w, h, panelX, panelW)
    box(panelX, 3, panelW, h - 4)
    writeAt(panelX + 2, 3, " Categories ")
    for i, cat in ipairs(categories) do
        local row = 3 + i
        if row > h - 2 then break end
        term.setCursorPos(panelX + 1, row)
        if state.focus == "cat" and i == state.catIdx then
            setBG(colors.blue); setFG(colors.white)
        else
            setBG(colors.black); setFG(colors.lightGray)
        end
        local label = " " .. cat .. " "
        label = label .. string.rep(" ", math.max(0, panelW - 2 - #label))
        term.write(label:sub(1, panelW - 2))
        resetColors()
    end
end

local function renderOptions(w, h, panelX, panelW)
    box(panelX, 3, panelW, h - 4)
    writeAt(panelX + 2, 3, " " .. categories[state.catIdx] .. " ")
    local opts = optionsFor(categories[state.catIdx], state.cfg)
    -- header row
    writeAt(panelX + 2, 4, string.format("%-22s %s", "Setting", "Value"))
    setFG(colors.gray)
    term.setCursorPos(panelX + 1, 5)
    term.write(string.rep(BOX_H, panelW - 2))
    resetColors()

    -- list
    local maxRows = h - 6 - 1
    for i, opt in ipairs(opts) do
        local row = 5 + i
        if row > h - 2 then break end
        term.setCursorPos(panelX + 1, row)
        if state.focus == "opt" and i == state.optIdx then
            setBG(colors.blue); setFG(colors.white)
        else
            setBG(colors.black); setFG(colors.lightGray)
        end
        local valStr = tostring(opt.get())
        local line = string.format(" %-20s %s", opt.label:sub(1,20), valStr:sub(1, panelW - 26))
        line = line .. string.rep(" ", math.max(0, panelW - 2 - #line))
        term.write(line:sub(1, panelW - 2))
        resetColors()
    end

    -- footer hint for kind
    local opt = opts[state.optIdx]
    if opt then
        setFG(colors.gray)
        writeAt(panelX + 2, h - 2, "Type: " .. opt.kind .. "  (Enter to edit)")
        resetColors()
    end
end

local function render()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()

    -- Title bar
    setBG(colors.blue); setFG(colors.white)
    term.setCursorPos(1, 1)
    local title = " ArchOS-CC Settings"
    if state.dirty then title = title .. " *" end
    title = title .. string.rep(" ", math.max(0, w - #title))
    term.write(title:sub(1, w))
    resetColors()

    -- Determine panel widths
    local catW = math.max(14, math.floor(w * 0.28))
    local optW = w - catW - 2

    renderCategories(w, h, 1, catW)
    renderOptions(w, h, catW + 2, optW)

    -- Footer / hotkey bar
    setBG(colors.lightGray); setFG(colors.black)
    term.setCursorPos(1, h)
    local bar = " Tab=switch focus  Up/Dn=navigate  Enter=edit  s=save  q=quit"
    if state.message ~= "" and (os.clock() - state.msgTime) < 3 then
        bar = " " .. state.message
    end
    bar = bar .. string.rep(" ", math.max(0, w - #bar))
    term.write(bar:sub(1, w))
    resetColors()
end

---------------------------------------------------------------- main ---

local function saveAll()
    saveSoftSettings()
    if _G.BIOS and _G.BIOS.saveConfig then
        _G.BIOS.saveConfig(state.cfg)
    end
    state.dirty = false
    msg("Settings saved")
end

local function main()
    loadSoftSettings()
    state.cfg = getConfig()

    while true do
        render()
        local event = { os.pullEvent() }
        local ev = event[1]

        if ev == "key" then
            local key = event[2]
            local opts = optionsFor(categories[state.catIdx], state.cfg)
            if key == keys.q then
                if state.dirty then
                    term.setCursorPos(1, select(2, term.getSize()))
                    term.clearLine()
                    setFG(colors.yellow)
                    term.write("Save changes before quitting? [Y/n] ")
                    setFG(colors.white)
                    local c = read()
                    if c == "" or c:lower() == "y" then
                        saveAll()
                    end
                end
                break
            elseif key == keys.tab then
                state.focus = (state.focus == "cat") and "opt" or "cat"
            elseif key == keys.up then
                if state.focus == "cat" then
                    state.catIdx = (state.catIdx == 1) and #categories or (state.catIdx - 1)
                    state.optIdx = 1
                else
                    state.optIdx = math.max(1, state.optIdx - 1)
                end
            elseif key == keys.down then
                if state.focus == "cat" then
                    state.catIdx = (state.catIdx == #categories) and 1 or (state.catIdx + 1)
                    state.optIdx = 1
                else
                    state.optIdx = math.min(#opts, state.optIdx + 1)
                end
            elseif key == keys.enter then
                if state.focus == "cat" then
                    -- switch to options panel
                    state.focus = "opt"
                else
                    local opt = opts[state.optIdx]
                    if opt then editOption(opt) end
                end
            elseif key == keys.left then
                state.focus = "cat"
            elseif key == keys.right then
                state.focus = "opt"
            end
        elseif ev == "char" then
            local c = event[2]:lower()
            if c == "s" then
                saveAll()
            elseif c == "q" then
                if state.dirty then
                    term.setCursorPos(1, select(2, term.getSize()))
                    term.clearLine()
                    setFG(colors.yellow)
                    term.write("Save changes before quitting? [Y/n] ")
                    setFG(colors.white)
                    local a = read()
                    if a == "" or a:lower() == "y" then saveAll() end
                end
                break
            end
        end
    end

    resetColors()
    term.clear()
    term.setCursorPos(1, 1)
    return 0
end

return main()
