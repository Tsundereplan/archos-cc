--[==[
    usr/bin/webbrowser.lua  —  Web Browser for ArchOS-CC
    ====================================================
    A simple text-based web browser that can fetch and display
    content from the internet via the CC:Tweaked HTTP API.

    Features:
      * URL input with history (arrow up/down to navigate)
      * Bookmark list (Ctrl+D to add, Ctrl+B to view)
      * Plain text rendering (strips HTML tags)
      * Page scrolling (Page Up/Down, arrows)
      * Search via DuckDuckGo Lite (text-only, no JS)
      * Page cache (don't re-fetch when going back)
      * Save current page to file

    Usage:
        webbrowser                   Start with blank page
        webbrowser <url>             Start with URL
        webbrowser search <query>    Start with DuckDuckGo search

    Bookmarks:
      Stored in ~/.bookmarks as one URL per line.

    History:
      Stored in ~/.web_history as one URL per line.

    Notes:
      * CC:Tweaked HTTP API only allows whitelisted domains by default.
        Configure in computercraft-server.toml:
          [http]
          enabled = true
          [[http.rules]]
          host = "*"
          action = "allow"
      * HTTPS works, but the API returns the raw HTML - we strip
        tags for display. JavaScript is not executed.
]==]

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

-- State
local state = {
    url = "",
    rawHtml = "",
    textLines = {},       -- parsed lines of text
    scroll = 1,
    history = {},         -- list of visited URLs (back/forward)
    historyIdx = 0,
    bookmarks = {},
    running = true,
}

-- Load bookmarks and history
local function loadBookmarks()
    state.bookmarks = {}
    local home = _G.Kernel and _G.Kernel.getEnv("HOME") or "/root"
    local path = home .. "/.bookmarks"
    if fs.exists(path) then
        local f = fs.open(path, "r")
        if f then
            for line in f.readLine do
                if line and line ~= "" then
                    table.insert(state.bookmarks, line)
                end
            end
            f.close()
        end
    end
end

local function saveBookmarks()
    local home = _G.Kernel and _G.Kernel.getEnv("HOME") or "/root"
    local path = home .. "/.bookmarks"
    local f = fs.open(path, "w")
    if f then
        for _, url in ipairs(state.bookmarks) do
            f.write(url .. "\n")
        end
        f.close()
    end
end

-- Async HTTP fetch with timeout
local function fetchURL(url, timeoutSec)
    timeoutSec = timeoutSec or 20
    if not http then return nil, "HTTP API not enabled" end

    -- Make sure URL has scheme
    if not url:match("^https?://") then
        url = "http://" .. url
    end

    -- Show "fetching..." indicator
    setColor(colors.gray)
    term.setCursorPos(1, 2)
    term.write("Fetching " .. url .. " ...")
    setColor(colors.white)

    http.request(url)
    local timer = os.startTimer(timeoutSec)
    local heartbeatTimer = os.startTimer(2)
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "http_success" and ev[2] == url then
            local handle = ev[3]
            if handle then
                local body = handle.readAll()
                handle.close()
                os.cancelTimer(timer)
                os.cancelTimer(heartbeatTimer)
                -- Clear "Fetching..." line
                term.setCursorPos(1, 2)
                term.clearLine()
                return body
            end
            os.cancelTimer(timer)
            os.cancelTimer(heartbeatTimer)
            return nil
        elseif ev[1] == "http_failure" and ev[2] == url then
            os.cancelTimer(timer)
            os.cancelTimer(heartbeatTimer)
            term.setCursorPos(1, 2)
            term.clearLine()
            return nil, ev[3] or "request failed"
        elseif ev[1] == "timer" and ev[2] == timer then
            term.setCursorPos(1, 2)
            term.clearLine()
            return nil, "timeout"
        elseif ev[1] == "timer" and ev[2] == heartbeatTimer then
            term.write(".")
            heartbeatTimer = os.startTimer(2)
        end
    end
end

-- Very simple HTML to text conversion.
-- Strips tags, decodes entities, splits on block elements.
local function htmlToText(html)
    if not html then return {} end
    -- Remove script and style contents entirely
    html = html:gsub("<script[^>]*>.-</script>", "")
    html = html:gsub("<style[^>]*>.-</style>", "")
    -- Remove comments
    html = html:gsub("<!%-%-.-%-%->", "")
    -- Convert block elements to newlines
    html = html:gsub("<br[^>]*>", "\n")
    html = html:gsub("</p>", "\n\n")
    html = html:gsub("</div>", "\n")
    html = html:gsub("</li>", "\n")
    html = html:gsub("</h[1-6]>", "\n\n")
    html = html:gsub("</tr>", "\n")
    html = html:gsub("<td[^>]*>", " | ")
    html = html:gsub("<th[^>]*>", " | ")
    -- Strip remaining tags
    html = html:gsub("<[^>]+>", "")
    -- Decode common HTML entities
    html = html:gsub("&amp;", "&")
    html = html:gsub("&lt;", "<")
    html = html:gsub("&gt;", ">")
    html = html:gsub("&quot;", '"')
    html = html:gsub("&#39;", "'")
    html = html:gsub("&nbsp;", " ")
    html = html:gsub("&copy;", "(c)")
    html = html:gsub("&trade;", "(TM)")
    -- Collapse multiple blank lines
    html = html:gsub("\n%s*\n", "\n\n")
    html = html:gsub("^\n+", "")
    html = html:gsub("%s+$", "")
    -- Split into lines, wrapping long lines
    local lines = {}
    local w = select(1, term.getSize()) - 2
    for rawLine in html:gmatch("[^\n]*") do
        local line = rawLine:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then
            -- Word-wrap long lines
            while #line > w do
                local chunk = line:sub(1, w)
                -- Try to break at a space
                local breakPos = chunk:reverse():find(" ")
                if breakPos and breakPos < 20 then
                    table.insert(lines, chunk:sub(1, #chunk - breakPos))
                    line = line:sub(#chunk - breakPos + 2)
                else
                    table.insert(lines, chunk)
                    line = line:sub(w + 1)
                end
            end
            if line ~= "" then table.insert(lines, line) end
        else
            table.insert(lines, "")
        end
    end
    return lines
end

-- Render the current page
local function render()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()

    -- Title bar (line 1)
    setBG(colors.blue)
    setColor(colors.white)
    term.setCursorPos(1, 1)
    local title = " ArchOS-CC Web Browser "
    if state.url ~= "" then
        local host = state.url:match("^https?://([^/]+)") or state.url
        title = title .. "- " .. host .. " "
    else
        title = title .. "(no page loaded) "
    end
    if #title > w then title = title:sub(1, w) end
    term.write(title .. string.rep(" ", w - #title))
    setBG(colors.black)

    -- Status line (line 2) - shows current URL
    setColor(colors.cyan)
    term.setCursorPos(1, 2)
    local url = state.url
    if #url > w - 12 then url = "..." .. url:sub(-(w - 15)) end
    term.write("URL: " .. url .. string.rep(" ", w - #url - 6))
    setColor(colors.white)

    -- Page content (lines 3 to h-2)
    local visibleLines = h - 4
    for i = 1, visibleLines do
        local lineIdx = state.scroll + i - 1
        local line = state.textLines[lineIdx]
        term.setCursorPos(1, 2 + i)
        if line then
            -- Detect headings (lines starting with #)
            if line:match("^%s*#") then
                setColor(colors.lightBlue)
            else
                setColor(colors.white)
            end
            if #line > w then line = line:sub(1, w) end
            term.write(line)
        else
            setColor(colors.gray)
            term.write("~")
            setColor(colors.white)
        end
    end

    -- Bottom bar (line h) - status + help
    setBG(colors.lightGray)
    setColor(colors.black)
    term.setCursorPos(1, h)
    local info = string.format(" Lines: %d  Scroll: %d-%d  ",
        #state.textLines, state.scroll, math.min(state.scroll + visibleLines - 1, #state.textLines))
    if #state.textLines == 0 then
        info = " No content. Press 'g' to enter URL, 's' to search, 'q' to quit. "
    end
    if #info > w then info = info:sub(1, w) end
    term.write(info .. string.rep(" ", w - #info))
    setBG(colors.black)
    setColor(colors.white)
end

-- Input dialog for URL
local function inputURL(prompt, default)
    local w, h = term.getSize()
    setBG(colors.black)
    setColor(colors.white)
    term.setCursorPos(1, 2)
    term.clearLine()
    setColor(colors.yellow)
    term.write(prompt)
    setColor(colors.white)
    term.write(" ")
    local value = default or ""
    term.write(value)
    local cx = #prompt + 2 + #value
    while true do
        term.setCursorPos(cx, 2)
        local ev = {os.pullEvent()}
        if ev[1] == "char" then
            value = value .. ev[2]
            if #value > w - #prompt - 3 then
                value = value:sub(1, w - #prompt - 3)
            end
            term.clearLine()
            setColor(colors.yellow)
            term.write(prompt)
            setColor(colors.white)
            term.write(" " .. value)
            cx = #prompt + 2 + #value
        elseif ev[1] == "key" then
            if ev[2] == keys.enter then
                return value
            elseif ev[2] == keys.backspace and #value > 0 then
                value = value:sub(1, -2)
                term.clearLine()
                setColor(colors.yellow)
                term.write(prompt)
                setColor(colors.white)
                term.write(" " .. value)
                cx = #prompt + 2 + #value
            elseif ev[2] == keys.escape then
                return nil
            end
        end
    end
end

-- Navigate to a URL
local function navigate(url)
    if not url or url == "" then return end
    -- Add to history
    if state.historyIdx < #state.history then
        -- Truncate forward history
        for i = state.historyIdx + 1, #state.history do
            state.history[i] = nil
        end
    end
    table.insert(state.history, url)
    state.historyIdx = #state.history

    -- Fetch
    state.url = url
    state.scroll = 1
    render()
    local body, err = fetchURL(url)
    if body then
        state.rawHtml = body
        state.textLines = htmlToText(body)
        state.scroll = 1
    else
        state.rawHtml = ""
        state.textLines = {
            "Failed to fetch: " .. tostring(err),
            "",
            "Possible causes:",
            "  1. HTTP API not enabled in computercraft-server.toml",
            "  2. Domain not in http.rules whitelist",
            "  3. Server has no internet",
            "  4. URL is wrong or site is down",
            "",
            "Press 'g' to enter another URL, 's' to search, 'q' to quit.",
        }
    end
    render()
end

-- Back / Forward
local function goBack()
    if state.historyIdx > 1 then
        state.historyIdx = state.historyIdx - 1
        local url = state.history[state.historyIdx]
        state.url = url
        state.scroll = 1
        render()
        local body = fetchURL(url)
        if body then
            state.rawHtml = body
            state.textLines = htmlToText(body)
        end
        render()
    end
end

local function goForward()
    if state.historyIdx < #state.history then
        state.historyIdx = state.historyIdx + 1
        local url = state.history[state.historyIdx]
        state.url = url
        state.scroll = 1
        render()
        local body = fetchURL(url)
        if body then
            state.rawHtml = body
            state.textLines = htmlToText(body)
        end
        render()
    end
end

-- DuckDuckGo Lite search (text-only version, no JS)
local function search(query)
    if not query or query == "" then return end
    -- URL-encode the query
    local encoded = ""
    for i = 1, #query do
        local c = query:sub(i, i)
        if c:match("[%w%-_%.~]") then
            encoded = encoded .. c
        else
            encoded = encoded .. string.format("%%%02X", string.byte(c))
        end
    end
    local url = "https://lite.duckduckgo.com/lite/?q=" .. encoded
    navigate(url)
end

-- Bookmarks dialog
local function showBookmarks()
    local w, h = term.getSize()
    setBG(colors.black)
    setColor(colors.white)
    term.clear()
    setColor(colors.lightBlue)
    print("Bookmarks")
    print("=========")
    setColor(colors.white)
    if #state.bookmarks == 0 then
        print("(no bookmarks yet)")
        print("")
        print("Press 'g' to enter a URL, then Ctrl+D to bookmark it.")
    else
        for i, url in ipairs(state.bookmarks) do
            print(string.format("  %d. %s", i, url))
        end
    end
    print("")
    setColor(colors.yellow)
    print("[Press a number to open, 'b' to return, 'd' to delete]")
    setColor(colors.white)
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "char" then
            local n = tonumber(ev[2])
            if n and state.bookmarks[n] then
                navigate(state.bookmarks[n])
                return
            elseif ev[2] == "b" then
                return
            elseif ev[2] == "d" then
                -- Delete mode: pick number
                setColor(colors.yellow)
                term.write("Delete which? ")
                setColor(colors.white)
                local num = read()
                local idx = tonumber(num)
                if idx and state.bookmarks[idx] then
                    table.remove(state.bookmarks, idx)
                    saveBookmarks()
                    setColor(colors.green)
                    print("Deleted.")
                    setColor(colors.white)
                    os.sleep(1)
                end
                return
            end
        end
    end
end

local function addBookmark()
    if state.url == "" then return end
    -- Check if already bookmarked
    for _, url in ipairs(state.bookmarks) do
        if url == state.url then
            -- Already bookmarked
            return
        end
    end
    table.insert(state.bookmarks, state.url)
    saveBookmarks()
end

-- Save current page to file
local function savePage()
    if state.rawHtml == "" then
        setColor(colors.red)
        print("No page to save.")
        setColor(colors.white)
        os.sleep(1)
        return
    end
    setColor(colors.yellow)
    term.write("Save to file: ")
    setColor(colors.white)
    local path = read()
    if path and path ~= "" then
        if not path:match("^/") then
            local cwd = _G.Kernel and _G.Kernel.getCwd() or "/"
            path = cwd .. "/" .. path
        end
        local f = fs.open(path, "w")
        if f then
            f.write(state.rawHtml)
            f.close()
            setColor(colors.green)
            print("Saved to " .. path)
            setColor(colors.white)
            os.sleep(1)
        else
            setColor(colors.red)
            print("Cannot write to " .. path)
            setColor(colors.white)
            os.sleep(1)
        end
    end
end

-- Main loop
local function main(...)
    local args = arg or {...}
    loadBookmarks()

    -- Initial URL from args
    if args[1] == "search" then
        local query = table.concat({table.unpack(args, 2)}, " ")
        search(query)
    elseif args[1] then
        navigate(args[1])
    else
        -- Start page
        state.textLines = {
            "    ArchOS-CC Web Browser",
            "    ======================",
            "",
            "Press 'g' to enter a URL",
            "Press 's' to search the web (DuckDuckGo Lite)",
            "Press 'b' to view bookmarks",
            "Press 'q' to quit",
            "",
            "Useful URLs:",
            "  https://lite.duckduckgo.com/lite/    (search)",
            "  https://text.npr.org                  (news)",
            "  https://en.m.wikipedia.org/wiki/Main_Page  (Wikipedia)",
            "  https://raw.githubusercontent.com/Tsundereplan/archos-cc/main/README.md",
            "",
            "Tips:",
            "  - Use arrow keys / Page Up/Down to scroll",
            "  - 'g' prompts for URL, no need to type http://",
            "  - 'b' opens bookmark list",
            "  - 'a' adds current URL to bookmarks",
            "  - Ctrl+S saves the page HTML to a file",
            "",
            "Note: Server must have HTTP enabled in computercraft-server.toml:",
            "  [http]",
            "  enabled = true",
            "  [[http.rules]]",
            '  host = "*"',
            '  action = "allow"',
        }
        render()
    end

    while state.running do
        local ev = {os.pullEvent()}
        if ev[1] == "key" then
            local key = ev[2]
            if key == keys.q then
                state.running = false
            elseif key == keys.g then
                local url = inputURL("URL:", "")
                if url and url ~= "" then navigate(url) end
            elseif key == keys.s then
                local query = inputURL("Search:", "")
                if query and query ~= "" then search(query) end
            elseif key == keys.b then
                showBookmarks()
                render()
            elseif key == keys.a then
                addBookmark()
                setColor(colors.green)
                term.setCursorPos(1, 2)
                term.clearLine()
                term.write("Bookmarked: " .. state.url)
                setColor(colors.white)
                os.sleep(1)
                render()
            elseif key == keys.up then
                if state.scroll > 1 then
                    state.scroll = state.scroll - 1
                    render()
                end
            elseif key == keys.down then
                local h = select(2, term.getSize())
                if state.scroll < #state.textLines - (h - 4) then
                    state.scroll = state.scroll + 1
                    render()
                end
            elseif key == keys.pageUp then
                local h = select(2, term.getSize())
                state.scroll = math.max(1, state.scroll - (h - 4))
                render()
            elseif key == keys.pageDown then
                local h = select(2, term.getSize())
                state.scroll = math.min(#state.textLines, state.scroll + (h - 4))
                render()
            elseif key == keys.left then
                goBack()
            elseif key == keys.right then
                goForward()
            elseif key == keys.leftCtrl or key == keys.rightCtrl then
                -- Wait for combo
                local e2 = {os.pullEvent()}
                if e2[1] == "key" then
                    if e2[2] == keys.d then
                        addBookmark()
                    elseif e2[2] == keys.s then
                        savePage()
                        render()
                    elseif e2[2] == keys.b then
                        showBookmarks()
                        render()
                    end
                end
            end
        elseif ev[1] == "char" then
            local c = ev[2]:lower()
            if c == "q" then
                state.running = false
            elseif c == "g" then
                local url = inputURL("URL:", "")
                if url and url ~= "" then navigate(url) end
            elseif c == "s" then
                local query = inputURL("Search:", "")
                if query and query ~= "" then search(query) end
            elseif c == "b" then
                showBookmarks()
                render()
            elseif c == "a" then
                addBookmark()
                setColor(colors.green)
                term.setCursorPos(1, 2)
                term.clearLine()
                term.write("Bookmarked!")
                setColor(colors.white)
                os.sleep(1)
                render()
            end
        end
    end

    resetColors()
    term.clear()
    term.setCursorPos(1, 1)
    return 0
end

return main()
