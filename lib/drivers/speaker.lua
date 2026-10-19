--[[
    lib/drivers/speaker.lua  —  Speaker driver
    =========================================
    Tracks attached speakers and provides simple sound playback:
      * playNote(instrument, volume, pitch)
      * playSound(name)  via speakers (if supported)
      * DFPWM audio streaming via cc.audio.dfpwm
]]

local Speaker = {}

Speaker.attached = {}  -- side -> { wrap, busy }

function Speaker.onAttach(side, wrap)
    if not wrap then wrap = peripheral.wrap(side) end
    Speaker.attached[side] = {
        side = side,
        wrap = wrap,
        busy = false,
    }
    if _G.BIOS and _G.BIOS.log then
        _G.BIOS.log("[speaker] Attached speaker at " .. side)
    end
end

function Speaker.onDetach(side)
    if Speaker.attached[side] then
        if _G.BIOS and _G.BIOS.log then
            _G.BIOS.log("[speaker] Detached speaker at " .. side)
        end
        Speaker.attached[side] = nil
    end
end

-- Play a note: instrument (string), volume (0-3), pitch (0-24)
function Speaker.playNote(side, instrument, volume, pitch)
    local info = Speaker.attached[side]
    if not info then return false, "no speaker at " .. side end
    if not info.wrap.playNote then return false, "speaker doesn't support playNote" end
    local ok, err = pcall(info.wrap.playNote, instrument, volume or 1, pitch or 12)
    return ok, err
end

-- Play a sound (CC:Tweaked 1.100+)
function Speaker.playSound(side, name, volume, pitch)
    local info = Speaker.attached[side]
    if not info then return false end
    if not info.wrap.playSound then return false, "playSound not supported" end
    return pcall(info.wrap.playSound, name, volume or 1, pitch or 1)
end

-- Play an audio chunk (DFPWM format)
function Speaker.playAudio(side, chunk)
    local info = Speaker.attached[side]
    if not info then return false end
    if not info.wrap.playAudio then return false end
    return pcall(info.wrap.playAudio, chunk)
end

-- Play a simple melody (sequence of notes)
function Speaker.playMelody(side, notes)
    local info = Speaker.attached[side]
    if not info then return false end
    for _, note in ipairs(notes) do
        Speaker.playNote(side, note.instrument or "harp", note.volume or 1, note.pitch or 12)
        os.sleep(note.duration or 0.2)
    end
    return true
end

function Speaker.list()
    local out = {}
    for side, info in pairs(Speaker.attached) do
        table.insert(out, info)
    end
    table.sort(out, function(a, b) return a.side < b.side end)
    return out
end

function Speaker.init(hw)
    if not hw or not hw.speakers then return end
    for _, wrap in ipairs(hw.speakers) do
        for _, side in ipairs({"top", "bottom", "left", "right", "front", "back"}) do
            if peripheral.getType(side) == "speaker" and peripheral.wrap(side) == wrap then
                Speaker.onAttach(side, wrap)
                break
            end
        end
    end
end

return Speaker
