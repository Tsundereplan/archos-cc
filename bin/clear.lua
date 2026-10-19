-- bin/clear.lua  —  Clear the terminal screen
-- Usage: clear

-- Clear the screen and reset the cursor to the top-left corner.
-- term is globally available in CC:Tweaked.
if term and term.clear and term.setCursorPos then
    term.clear()
    term.setCursorPos(1, 1)
end
return 0
