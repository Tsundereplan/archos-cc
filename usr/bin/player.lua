--[[
    usr/bin/player.lua  —  Audio player for CC:Tweaked speakers
    =========================================================
    Usage:
      player note <instrument> <pitch>          Play one note
      player melody <file>                       Play melody from file
                                                (format: instrument,pitch,duration)
      player song                                Interactive piano mode
      player list                                List available instruments

    Instruments (CC:Tweaked):
      harp basedrum snare hat bass flute bell guitar xylophone
      iron_xylophone pling banjo

    Piano mode keymap (pitch 0-24):
      a s d f g h j k l   -> pitches  0..8   (one octave, harp)
      w e   t y u   o p   -> pitches 12..19  (one octave up)
      z x c v b n m       -> pitches  0..5   (bass instrument)
      1-9                 -> percussion  (hat / snare / basedrum cycle)

    Piano mode hotkeys:
      i  cycle instrument for the white-key row
      + / -  raise / lower octave offset
      q  quit piano mode
]]

local args = arg or {...}

-- All valid CC:Tweaked instruments
local INSTRUMENTS = {
    "harp", "basedrum", "snare", "hat", "bass", "flute",
    "bell", "guitar", "xylophone", "iron_xylophone", "pling", "banjo",
}

local function isInstrument(name)
    for _, v in ipairs(INSTRUMENTS) do if v == name then return true end end
    return false
end

-- Find an attached speaker. Try BIOS driver first, then direct scan.
local function findSpeaker()
    if _G.Drivers and _G.Drivers.speaker and _G.Drivers.speaker.list then
        local list = _G.Drivers.speaker.list()
        if list and #list > 0 then
            return list[1].wrap, list[1].side
        end
    end
    if _G.BIOS and _G.BIOS.hw and _G.BIOS.hw.speakers then
        if #(_G.BIOS.hw.speakers) > 0 then
            return _G.BIOS.hw.speakers[1], "?"
        end
    end
    -- direct peripheral scan
    local sides = {"top","bottom","left","right","front","back"}
    for _, s in ipairs(sides) do
        if peripheral.isPresent and peripheral.isPresent(s)
           and peripheral.getType(s) == "speaker" then
            return peripheral.wrap(s), s
        end
    end
    return nil
end

local function playNote(speaker, instrument, pitch, volume)
    if not speaker or not speaker.playNote then return false, "no speaker" end
    volume = volume or 1.0
    pitch = pitch or 12
    if pitch < 0 then pitch = 0 end
    if pitch > 24 then pitch = 24 end
    local ok, err = pcall(speaker.playNote, instrument, volume, pitch)
    return ok, err
end

local function playSound(speaker, name, volume, pitch)
    if not speaker or not speaker.playSound then return false, "playSound not supported" end
    return pcall(speaker.playSound, name, volume or 1, pitch or 1)
end

-- Print helpers
local function errExit(msg)
    io.stderr:write("player: " .. msg .. "\n")
    return 1
end

local function colorPrint(c, s)
    if term.isColor() then term.setTextColor(c) end
    print(s)
    if term.isColor() then term.setTextColor(colors.white) end
end

local function printUsage()
    print([[Usage: player <command> [args]
Commands:
  note <instrument> <pitch>   Play a single note (pitch 0-24)
  melody <file>               Play melody from file (instrument,pitch,duration per line)
  song                        Interactive piano mode
  list                        List available instruments
  sound <name> [vol] [pitch] Play a sound (CC:T 1.100+)]])
end

---------------------------------------------------------------- subcommands ---

local function cmdList()
    print("Available instruments (CC:Tweaked):")
    for _, v in ipairs(INSTRUMENTS) do
        print("  " .. v)
    end
    return 0
end

local function cmdNote(instrument, pitchStr)
    if not instrument or not isInstrument(instrument) then
        return errExit("invalid instrument. Try 'player list'.")
    end
    local pitch = tonumber(pitchStr)
    if not pitch then return errExit("invalid pitch (must be 0-24)") end
    local speaker, side = findSpeaker()
    if not speaker then return errExit("no speaker attached") end
    local ok, err = playNote(speaker, instrument, pitch)
    if not ok then return errExit("playback failed: " .. tostring(err)) end
    io.stderr:write(string.format("player: %s @ pitch %d on side %s\n", instrument, pitch, side or "?"))
    return 0
end

local function cmdSound(name, volStr, pitchStr)
    local speaker = findSpeaker()
    if not speaker then return errExit("no speaker attached") end
    local vol = tonumber(volStr) or 1
    local pitch = tonumber(pitchStr) or 1
    local ok, err = playSound(speaker, name, vol, pitch)
    if not ok then return errExit("playSound failed: " .. tostring(err)) end
    io.stderr:write(string.format("player: sound %s vol=%.2f pitch=%.2f\n", name, vol, pitch))
    return 0
end

local function cmdMelody(filePath)
    if not filePath then return errExit("melody requires a file path") end
    local f = fs.open(filePath, "r")
    if not f then return errExit("cannot open: " .. filePath) end
    local content = f.readAll()
    f.close()

    local speaker, side = findSpeaker()
    if not speaker then return errExit("no speaker attached") end

    local count = 0
    for lineNum, line in ipairs(content:gmatch("[^\r\n]+")) do
        -- strip comments and whitespace
        line = line:gsub("%s+$", ""):gsub("^%s+", "")
        if line == "" or line:sub(1, 1) == "#" then
            -- skip
        else
            local inst, pitch, dur = line:match("^([^,]+),([^,]+),([^,]+)$")
            if not inst then
                inst, pitch = line:match("^([^,]+),([^,]+)$")
                dur = "0.2"
            end
            if inst then
                inst = inst:gsub("^%s+", ""):gsub("%s+$", "")
                if not isInstrument(inst) then
                    io.stderr:write(string.format("player: line %d: invalid instrument '%s'\n", lineNum, inst))
                else
                    local p = tonumber(pitch)
                    local d = tonumber(dur) or 0.2
                    if p then
                        playNote(speaker, inst, p)
                        count = count + 1
                        os.sleep(d)
                    end
                end
            end
        end
    end
    io.stderr:write(string.format("player: played %d notes on side %s\n", count, side or "?"))
    return 0
end

-- Piano mode: keyboard-to-pitch mapping
local KEYMAP_WHITE = {
    a = 0,  s = 2,  d = 4,  f = 5,  g = 7,  h = 9,  j = 11, k = 12, l = 14,
}
local KEYMAP_BLACK = {
    w = 1,  e = 3,  t = 6,  y = 8,  u = 10, o = 13, p = 15,
}
local KEYMAP_BASS = {
    z = 0,  x = 2,  c = 4,  v = 5,  b = 7,  n = 9,  m = 11,
}

local function renderPiano(w, h, state)
    term.setBackgroundColor(colors.black)
    term.clear()

    -- Title
    if term.isColor() then
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
    end
    term.setCursorPos(1, 1)
    local title = " ArchOS-CC Player - Piano Mode "
    title = title .. string.rep(" ", math.max(0, w - #title))
    term.write(title:sub(1, w))
    if term.isColor() then
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
    end

    -- Status
    term.setCursorPos(1, 2)
    if term.isColor() then term.setTextColor(colors.yellow) end
    term.write(string.format(" Instrument: %-16s  Octave: %+d  Pressed: %s",
        state.instrument, state.octave, state.lastKey or "(none)"))
    if term.isColor() then term.setTextColor(colors.white) end

    -- Piano keyboard visualization
    local kbY = math.max(4, math.floor(h / 2))
    local whiteKeys = { "a","s","d","f","g","h","j","k","l" }
    local blackKeys = { "w","e","t","y","u","o","p" }
    -- white row
    local totalWhite = #whiteKeys
    local whiteW = math.floor((w - 2) / totalWhite)
    local startX = math.floor((w - (whiteW * totalWhite)) / 2) + 1

    -- Draw white keys (3 rows tall)
    for i, k in ipairs(whiteKeys) do
        local x = startX + (i - 1) * whiteW
        if term.isColor() then
            term.setBackgroundColor(state.pressed == k and colors.lightBlue or colors.white)
            term.setTextColor(colors.black)
        end
        for r = 0, 2 do
            term.setCursorPos(x, kbY + r)
            term.write(string.rep(" ", whiteW - 1))
        end
        term.setCursorPos(x + math.floor(whiteW/2), kbY + 1)
        term.write(k)
        -- pitch label below
        term.setCursorPos(x + math.floor(whiteW/2) - 1, kbY + 3)
        if term.isColor() then term.setTextColor(colors.gray) end
        local p = (KEYMAP_WHITE[k] or 0) + state.octave * 12
        term.write(string.format("%2d", p))
        if term.isColor() then term.setTextColor(colors.black) end
    end

    -- Draw black keys (1 row, between whites)
    for i, k in ipairs(blackKeys) do
        -- position roughly between certain white keys
        local pos = ({ [1]=1, [2]=2, [3]=4, [4]=5, [5]=6, [6]=8, [7]=9 })[i]
        if pos then
            local x = startX + pos * whiteW - math.floor(whiteW/4)
            if term.isColor() then
                term.setBackgroundColor(state.pressed == k and colors.purple or colors.gray)
                term.setTextColor(colors.white)
            end
            term.setCursorPos(x, kbY)
            term.write(string.rep(" ", math.max(2, math.floor(whiteW/2))))
            term.setCursorPos(x + math.floor(whiteW/4) - 1, kbY)
            term.write(k)
            -- pitch label
            if term.isColor() then term.setTextColor(colors.gray) end
            term.setCursorPos(x + math.floor(whiteW/4) - 1, kbY + 3)
            local p = (KEYMAP_BLACK[k] or 0) + state.octave * 12
            term.write(string.format("%2d", p))
        end
    end
    if term.isColor() then
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
    end

    -- Bass row hint
    term.setCursorPos(1, kbY + 5)
    if term.isColor() then term.setTextColor(colors.lightGray) end
    term.write(" Bass row (z-m)  |  i=change instrument  +/-=octave  q=quit")
    if term.isColor() then term.setTextColor(colors.white) end

    -- Help
    term.setCursorPos(1, h - 1)
    if term.isColor() then term.setTextColor(colors.gray) end
    term.write(" Press a-l for harp notes, w-p for sharps, z-m for bass. 'q' to quit.")
    if term.isColor() then term.setTextColor(colors.white) end
end

local function cmdSong()
    local speaker, side = findSpeaker()
    if not speaker then return errExit("no speaker attached") end

    local state = {
        instrument = "harp",
        bassInstrument = "bass",
        octave = 0,
        lastKey = nil,
        pressed = nil,
    }

    local w, h = term.getSize()

    local function handleKey(c)
        if c == "q" then return "quit" end
        if c == "i" then
            -- cycle instrument
            for i, v in ipairs(INSTRUMENTS) do
                if v == state.instrument then
                    state.instrument = INSTRUMENTS[(i % #INSTRUMENTS) + 1]
                    return
                end
            end
            state.instrument = "harp"
            return
        end
        if c == "+" or c == "=" then
            state.octave = math.min(2, state.octave + 1)
            return
        end
        if c == "-" or c == "_" then
            state.octave = math.max(-2, state.octave - 1)
            return
        end

        local pitch
        local inst = state.instrument
        if KEYMAP_WHITE[c] then
            pitch = KEYMAP_WHITE[c] + state.octave * 12
        elseif KEYMAP_BLACK[c] then
            pitch = KEYMAP_BLACK[c] + state.octave * 12
        elseif KEYMAP_BASS[c] then
            pitch = KEYMAP_BASS[c]
            inst = state.bassInstrument
        elseif c == "1" then
            playNote(speaker, "hat", 12)
            state.lastKey = c; state.pressed = c
            return
        elseif c == "2" then
            playNote(speaker, "snare", 12)
            state.lastKey = c; state.pressed = c
            return
        elseif c == "3" then
            playNote(speaker, "basedrum", 12)
            state.lastKey = c; state.pressed = c
            return
        end
        if pitch then
            if pitch < 0 then pitch = 0 end
            if pitch > 24 then pitch = 24 end
            playNote(speaker, inst, pitch)
            state.lastKey = c
            state.pressed = c
        end
    end

    while true do
        renderPiano(w, h, state)
        local event = { os.pullEvent() }
        local ev = event[1]
        if ev == "char" then
            local c = event[2]:lower()
            local r = handleKey(c)
            if r == "quit" then break end
        elseif ev == "key" then
            if event[2] == keys.q then break end
        elseif ev == "term_resize" then
            w, h = term.getSize()
        end
        -- clear pressed indicator shortly after
        -- (rendered next loop; "pressed" persists one frame for visual feedback)
        if state.pressed then
            os.startTimer(0.1)
        end
        if ev == "timer" then
            state.pressed = nil
        end
    end

    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    return 0
end

---------------------------------------------------------------- main ---

local function main()
    local cmd = args[1]
    if not cmd or cmd == "-h" or cmd == "--help" then
        printUsage()
        return 0
    end

    if cmd == "list" then
        return cmdList()
    elseif cmd == "note" then
        return cmdNote(args[2], args[3])
    elseif cmd == "sound" then
        return cmdSound(args[2], args[3], args[4])
    elseif cmd == "melody" then
        return cmdMelody(args[2])
    elseif cmd == "song" then
        return cmdSong()
    else
        io.stderr:write("player: unknown command '" .. cmd .. "'\n")
        printUsage()
        return 1
    end
end

return main()
