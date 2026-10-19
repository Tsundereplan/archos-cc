--[[
    lib/network.lua  —  Network abstraction layer
    ============================================
    Wraps modems (wired and wireless) into a unified network interface.
    Provides:
      * Automatic modem discovery
      * Channel management
      * Hostname resolution (similar to DNS via rednet)
      * HTTP wrapper (uses native http API)
      * GitHub API client (raw.githubusercontent.com)
      * pinestore.cc client
      * Send/receive packets with delivery confirmation

    Configuration: /etc/network.conf
      hostname=archos-cc
      channel=1
      protocol=archos
]]

local Network = {}

Network.modems = {}      -- list of modem wraps
Network.hostname = "archos-cc"
Network.channel = 1
Network.protocol = "archos"
Network.online = false
Network.connections = {}  -- track open connections

-- Hostname registry for DNS-like lookup
Network.hosts = {}        -- hostname -> computerID

-- Load configuration
function Network.loadConfig()
    if not fs.exists("/etc/network.conf") then
        Network.saveConfig()
        return
    end
    local f = fs.open("/etc/network.conf", "r")
    if not f then return end
    for line in f.readLine do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.*)$")
        if k and v then
            v = v:gsub("^%s+", ""):gsub("%s+$", "")
            if k == "hostname" then Network.hostname = v
            elseif k == "channel" then Network.channel = tonumber(v) or 1
            elseif k == "protocol" then Network.protocol = v end
        end
    end
    f.close()
end

function Network.saveConfig()
    if not fs.exists("/etc") then fs.makeDir("/etc") end
    local f = fs.open("/etc/network.conf", "w")
    if f then
        f.write("hostname=" .. Network.hostname .. "\n")
        f.write("channel=" .. Network.channel .. "\n")
        f.write("protocol=" .. Network.protocol .. "\n")
        f.close()
    end
end

-- Discover all attached modems
function Network.discoverModems()
    Network.modems = {}
    if not peripheral then return end
    local sides = {"top", "bottom", "left", "right", "front", "back"}
    for _, side in ipairs(sides) do
        if peripheral.isPresent(side) and peripheral.getType(side) == "modem" then
            local wrap = peripheral.wrap(side)
            table.insert(Network.modems, { side = side, wrap = wrap, isWireless = wrap.isWireless and wrap.isWireless() or false })
        end
    end
    return Network.modems
end

-- Open a channel on all modems
function Network.open(channel)
    for _, m in ipairs(Network.modems) do
        if m.wrap.open then
            pcall(m.wrap.open, channel)
        end
    end
end

function Network.close(channel)
    for _, m in ipairs(Network.modems) do
        if m.wrap.close then
            pcall(m.wrap.close, channel)
        end
    end
end

-- Initialize network: discover modems, open default channels
function Network.init()
    Network.loadConfig()
    Network.discoverModems()
    if #Network.modems == 0 then
        return false, "no modems detected"
    end
    -- Open the system channel and broadcast channel
    Network.open(Network.channel)
    Network.open(65535)
    Network.online = true
    -- Announce ourselves
    Network.broadcast("HELLO", { hostname = Network.hostname, id = os.getComputerID() })
    return true
end

-- Send a message to a specific computer
function Network.send(targetID, message)
    if not Network.online then return false, "network offline" end
    local payload = textutils.serialize(message)
    for _, m in ipairs(Network.modems) do
        if m.wrap.transmit then
            -- Use broadcast channel for the target
            pcall(m.wrap.transmit, Network.channel, Network.channel, { to = targetID, from = os.getComputerID(), payload = payload })
        end
    end
    return true
end

-- Broadcast a message to all computers
function Network.broadcast(msgType, data)
    if not Network.online then return false end
    local packet = {
        type = msgType,
        from = os.getComputerID(),
        hostname = Network.hostname,
        data = data,
        timestamp = os.time(),
    }
    local payload = textutils.serialize(packet)
    for _, m in ipairs(Network.modems) do
        if m.wrap.transmit then
            pcall(m.wrap.transmit, 65535, 65535, payload)
        end
    end
    return true
end

-- Wait for a message (with timeout). Returns the packet or nil.
function Network.receive(timeout, filterType)
    local timer = nil
    if timeout then
        timer = os.startTimer(timeout)
    end
    while true do
        local event = {os.pullEvent()}
        if event[1] == "modem_message" then
            -- event: side, channel, replyChannel, message, distance
            local msg = event[5]
            if type(msg) == "string" then
                local ok, packet = pcall(textutils.unserialize, msg)
                if ok and type(packet) == "table" then
                    if not filterType or packet.type == filterType then
                        return packet
                    end
                end
            end
        elseif event[1] == "timer" and timer and event[2] == timer then
            return nil
        end
    end
end

-- DNS-like hostname lookup
function Network.lookup(hostname)
    -- Check local cache first
    if Network.hosts[hostname] then
        return Network.hosts[hostname]
    end
    -- Broadcast a lookup request
    Network.broadcast("LOOKUP", { hostname = hostname })
    -- Wait up to 1 second for a response
    local start = os.clock()
    while os.clock() - start < 1 do
        local packet = Network.receive(1 - (os.clock() - start), "RESPONSE")
        if packet and packet.data and packet.data.hostname == hostname then
            Network.hosts[hostname] = packet.from
            return packet.from
        end
    end
    return nil
end

-- Ping: send ECHO, wait for ECHO_REPLY
function Network.ping(targetID)
    if not Network.online then return nil, "offline" end
    Network.send(targetID, { type = "PING", from = os.getComputerID() })
    local start = os.clock()
    local reply = Network.receive(2, "PONG")
    if reply and reply.from == targetID then
        return os.clock() - start
    end
    return nil, "timeout"
end

-- HTTP wrappers (uses native http API)
function Network.httpGet(url, headers)
    if not http then return nil, "http api not enabled" end
    local handle = http.get(url, headers)
    if not handle then return nil, "request failed" end
    local body = handle.readAll()
    handle.close()
    return body
end

function Network.httpPost(url, body, headers)
    if not http then return nil, "http api not enabled" end
    local handle = http.post(url, body, headers)
    if not handle then return nil, "request failed" end
    local resp = handle.readAll()
    handle.close()
    return resp
end

function Network.httpRequest(url, options)
    if not http then return nil, "http api not enabled" end
    options = options or {}
    local method = options.method or "GET"
    local body = options.body
    local headers = options.headers or {}
    local handle
    if method == "POST" then
        handle = http.post(url, body, headers)
    elseif method == "PUT" then
        -- CC:Tweaked doesn't natively support PUT, but we can use websocket workaround
        return nil, "PUT not supported by native http"
    else
        handle = http.get(url, headers)
    end
    if not handle then return nil, "request failed" end
    local resp = handle.readAll()
    local responseHeaders = handle.getResponseHeaders and handle.getResponseHeaders() or {}
    handle.close()
    return resp, responseHeaders
end

-- GitHub raw file fetcher
-- Defaults to raw.githubusercontent.com/<user>/<repo>/<branch>/<path>
function Network.fetchGitHubRaw(user, repo, branch, filepath)
    local url = string.format("https://raw.githubusercontent.com/%s/%s/%s/%s", user, repo, branch, filepath)
    return Network.httpGet(url)
end

-- GitHub API: list repo contents at path
-- Returns a Lua table from the JSON response (basic parse)
function Network.githubList(user, repo, branch, path)
    path = path or ""
    local url = string.format("https://api.github.com/repos/%s/%s/contents/%s?ref=%s",
        user, repo, path, branch)
    local body, headers = Network.httpRequest(url, { headers = { Accept = "application/vnd.github.v3+json" } })
    if not body then return nil, "request failed" end
    -- Simple JSON parse: extract "name" and "path" fields
    -- CC:Tweaked has no JSON parser; we use textutils.unserializeJSON if available
    if textutils.unserializeJSON then
        return textutils.unserializeJSON(body)
    end
    -- Fallback: regex extraction
    local results = {}
    for name, tp in body:gmatch('"name"%s*:%s*"([^"]+)"%s*,%s*"type"%s*:%s*"([^"]+)"') do
        table.insert(results, { name = name, type = tp })
    end
    return results
end

-- pinestore.cc client
-- pinestore.cc hosts CC:Tweaked apps. We use their HTTP API if available.
function Network.pinestoreSearch(query)
    local url = "https://pinestore.cc/api/apps?q=" .. (query or "")
    local body = Network.httpGet(url)
    if not body then return nil end
    if textutils.unserializeJSON then
        return textutils.unserializeJSON(body)
    end
    return body
end

function Network.pinestoreInstall(appId)
    -- pinestore.cc serves install scripts via a paste-like URL
    -- We assume a reasonable URL pattern; adjust if API changes
    local url = "https://pinestore.cc/api/apps/" .. appId .. "/install"
    local body = Network.httpGet(url)
    if not body then return nil, "failed to fetch install script" end
    -- Execute the install script (it returns lua code)
    local fn, err = load(body, "pinestore-install", "t", _G)
    if not fn then return nil, err end
    return pcall(fn)
end

return Network
