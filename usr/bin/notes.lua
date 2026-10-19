-- usr/bin/notes.lua  —  Sticky notes / todo app
-- Notes are stored in ~/.notes, one per line: "X|TITLE|CONTENT"
--   X = " " (not done) or "X" (done)
--
-- Subcommands:
--   notes            show all notes (numbered list with title + preview)
--   notes add        prompt for title and content, append to list
--   notes del <N>    delete note number N
--   notes view <N>   show the full contents of note N
--   notes edit <N>   open note N's content in /usr/bin/editor.lua
--   notes toggle <N> flip the done flag of note N

local FS     = _G.FS or fs
local Kernel = _G.Kernel

local HOME = (Kernel and Kernel.getEnv and Kernel.getEnv("HOME")) or "/home"
local notesFile = HOME .. "/.notes"

-- Read the notes file into a list of {flag=, title=, content=}
local function readNotes()
    local notes = {}
    if not FS.exists(notesFile) then return notes end
    local f = FS.open(notesFile, "r")
    if not f then return notes end
    local line = f.readLine and f.readLine() or nil
    while line do
        -- Parse "X|TITLE|CONTENT" - title may not contain |, content may
        local flag, rest = line:match("^([%sX])|(.*)$")
        if flag and rest then
            local title, content = rest:match("^([^|]*)|(.*)$")
            if title then
                table.insert(notes, {
                    flag = flag,
                    title = title,
                    content = content,
                })
            else
                -- No content separator - title only, empty content
                table.insert(notes, { flag = flag, title = rest, content = "" })
            end
        end
        line = f.readLine and f.readLine()
    end
    f.close()
    return notes
end

-- Persist the notes list back to ~/.notes (overwrites)
local function saveNotes(notes)
    local f = FS.open(notesFile, "w")
    if not f then
        io.stderr:write("notes: cannot write to " .. notesFile .. "\n")
        return false
    end
    for _, n in ipairs(notes) do
        -- Ensure single-line content (replace newlines with spaces)
        local safeContent = n.content:gsub("\n", " ")
        local safeTitle   = n.title:gsub("\n", " ")
        f.writeLine((n.flag or " ") .. "|" .. safeTitle .. "|" .. safeContent)
    end
    f.close()
    return true
end

-- Show all notes as a numbered list
local function showAll(notes)
    if #notes == 0 then
        print("No notes yet.  Use 'notes add' to create one.")
        return 0
    end
    if term.isColor() then
        term.setTextColor(colors.cyan)
    end
    print(string.format("  %-4s %-22s %s", "#", "Title", "Preview"))
    if term.isColor() then term.setTextColor(colors.gray) end
    print("  " .. string.rep("-", 60))
    for i, n in ipairs(notes) do
        local done = (n.flag == "X") and "[X]" or "[ ]"
        local preview = n.content:gsub("\n", " ")
        if preview == "" then preview = "(empty)" end
        preview = preview:sub(1, 30)
        local title = n.title:sub(1, 22)
        if term.isColor() then
            term.setTextColor(n.flag == "X" and colors.green or colors.white)
        end
        print(string.format("  %-4d %-3s %-22s %s", i, done, title, preview))
    end
    if term.isColor() then term.setTextColor(colors.white) end
    print("")
    print(string.format("Total: %d notes", #notes))
    return 0
end

-- Add a new note (prompts the user)
local function addNote()
    if term.isColor() then term.setTextColor(colors.yellow) end
    term.write("Title: ")
    if term.isColor() then term.setTextColor(colors.white) end
    local title = read()
    if not title or title == "" then
        print("Aborted.")
        return 1
    end
    if term.isColor() then term.setTextColor(colors.yellow) end
    term.write("Content (single line): ")
    if term.isColor() then term.setTextColor(colors.white) end
    local content = read() or ""
    local notes = readNotes()
    table.insert(notes, { flag = " ", title = title, content = content })
    if saveNotes(notes) then
        print("Note added as #" .. #notes)
        return 0
    end
    return 1
end

-- Delete note number N
local function deleteNote(n)
    local notes = readNotes()
    if n < 1 or n > #notes then
        io.stderr:write("notes: no note #" .. tostring(n) .. "\n")
        return 1
    end
    local removed = table.remove(notes, n)
    saveNotes(notes)
    print("Deleted note #" .. n .. " ('" .. removed.title .. "')")
    return 0
end

-- View the full contents of note N
local function viewNote(n)
    local notes = readNotes()
    if n < 1 or n > #notes then
        io.stderr:write("notes: no note #" .. tostring(n) .. "\n")
        return 1
    end
    local note = notes[n]
    if term.isColor() then term.setTextColor(colors.cyan) end
    print("========================================")
    print(" Note #" .. n)
    print("========================================")
    if term.isColor() then term.setTextColor(colors.yellow) end
    term.write("Title:   ")
    if term.isColor() then term.setTextColor(colors.white) end
    print(note.title)
    if term.isColor() then term.setTextColor(colors.yellow) end
    term.write("Done:    ")
    if term.isColor() then term.setTextColor(colors.white) end
    print(note.flag == "X" and "yes" or "no")
    if term.isColor() then term.setTextColor(colors.yellow) end
    term.write("Content: ")
    if term.isColor() then term.setTextColor(colors.white) end
    print(note.content)
    if term.isColor() then term.setTextColor(colors.gray) end
    print("----------------------------------------")
    if term.isColor() then term.setTextColor(colors.white) end
    return 0
end

-- Toggle the done flag on note N
local function toggleNote(n)
    local notes = readNotes()
    if n < 1 or n > #notes then
        io.stderr:write("notes: no note #" .. tostring(n) .. "\n")
        return 1
    end
    notes[n].flag = (notes[n].flag == "X") and " " or "X"
    saveNotes(notes)
    print("Note #" .. n .. " marked as: " ..
        (notes[n].flag == "X" and "done" or "not done"))
    return 0
end

-- Edit note N's content in the editor
local function editNote(n)
    local notes = readNotes()
    if n < 1 or n > #notes then
        io.stderr:write("notes: no note #" .. tostring(n) .. "\n")
        return 1
    end
    -- Use a temp file under /tmp (or HOME if /tmp doesn't exist)
    local tmpDir = "/tmp"
    if not FS.exists(tmpDir) then tmpDir = HOME end
    if not FS.exists(tmpDir) then fs.makeDir(FS.resolve(tmpDir)) end
    local tmpFile = tmpDir .. "/.note_edit_" .. tostring(os.getComputerID and os.getComputerID() or 0)

    -- Write current content to the temp file
    local f = FS.open(tmpFile, "w")
    if not f then
        io.stderr:write("notes: cannot open temp file for writing\n")
        return 1
    end
    f.write(notes[n].content)
    f.close()

    -- Launch the editor on the temp file
    if Kernel and Kernel.exec then
        local pid = Kernel.exec("/usr/bin/editor.lua", { tmpFile })
        if pid and Kernel.wait then Kernel.wait(pid) end
    else
        pcall(function()
            if shell and shell.run then shell.run("/usr/bin/editor.lua", tmpFile) end
        end)
    end

    -- Read back the modified content
    if FS.exists(tmpFile) then
        local f2 = FS.open(tmpFile, "r")
        if f2 then
            local newContent = f2.readAll()
            f2.close()
            notes[n].content = newContent or ""
            -- Clean up temp file
            if FS.delete then FS.delete(tmpFile) else fs.delete(FS.resolve(tmpFile)) end
            saveNotes(notes)
            print("Note #" .. n .. " updated.")
            return 0
        end
    end
    return 1
end

-- Print usage information
local function usage()
    io.stderr:write("Usage: notes [add|del N|view N|edit N|toggle N]\n")
    io.stderr:write("  notes            show all notes\n")
    io.stderr:write("  notes add        create a new note\n")
    io.stderr:write("  notes del <N>    delete note N\n")
    io.stderr:write("  notes view <N>   show full contents of note N\n")
    io.stderr:write("  notes edit <N>   edit note N in editor\n")
    io.stderr:write("  notes toggle <N> toggle done flag on note N\n")
    return 1
end

-- Main dispatch
-- Args are captured at file scope so the script works both under
-- Kernel.exec (which sets the global `arg`) and direct invocation.
local scriptArgs = arg or {}

local function main()
    local args = scriptArgs
    if #args == 0 then
        return showAll(readNotes())
    end

    local cmd = args[1]
    if cmd == "add" then
        return addNote()
    elseif cmd == "del" or cmd == "rm" then
        local n = tonumber(args[2])
        if not n then io.stderr:write("notes: del requires a number\n"); return 1 end
        return deleteNote(n)
    elseif cmd == "view" or cmd == "show" then
        local n = tonumber(args[2])
        if not n then io.stderr:write("notes: view requires a number\n"); return 1 end
        return viewNote(n)
    elseif cmd == "edit" then
        local n = tonumber(args[2])
        if not n then io.stderr:write("notes: edit requires a number\n"); return 1 end
        return editNote(n)
    elseif cmd == "toggle" or cmd == "done" then
        local n = tonumber(args[2])
        if not n then io.stderr:write("notes: toggle requires a number\n"); return 1 end
        return toggleNote(n)
    elseif cmd == "-h" or cmd == "--help" or cmd == "help" then
        return usage()
    else
        io.stderr:write("notes: unknown command '" .. cmd .. "'\n")
        return usage()
    end
end

return main()
