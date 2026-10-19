-- bin/ping.lua  —  Send ICMP-like echo requests to another host
-- Usage: ping [-c COUNT] <hostname_or_id>

local Network = _G.Network
local args    = {...}

local hasColor = term.isColor and term.isColor()
local function c(col, fn)
    if hasColor then term.setTextColor(col) end
    fn()
    if hasColor then term.setTextColor(colors.white) end
end

-- Parse args
local count = 4
local target = nil
local i = 1
while i <= #args do
    local a = args[i]
    if a == "-c" then
        local n = tonumber(args[i + 1])
        if not n then
            io.stderr:write("ping: -c requires a numeric argument\n")
            return 1
        end
        count = n
        i = i + 2
    elseif a == "-h" or a == "--help" then
        print("Usage: ping [-c COUNT] <hostname_or_id>")
        print("Send ICMP-like echo packets to another ArchOS host.")
        print("  -c COUNT   number of packets to send (default: 4)")
        return 0
    elseif a:sub(1, 2) == "-c" and #a > 2 then
        -- combined -c5 form
        local n = tonumber(a:sub(3))
        if not n then
            io.stderr:write("ping: invalid -c argument\n")
            return 1
        end
        count = n
        i = i + 1
    else
        target = a
        i = i + 1
    end
end

if not target then
    io.stderr:write("ping: missing host operand\n")
    io.stderr:write("Usage: ping [-c COUNT] <hostname_or_id>\n")
    return 1
end

if not Network then
    io.stderr:write("ping: network subsystem unavailable\n")
    return 1
end

if not Network.online then
    c(colors.red, function()
        io.stderr:write("ping: connect: Network is unreachable\n")
    end)
    return 1
end

-- Resolve target to an ID
local targetID
local resolvedName
if tonumber(target) then
    targetID = tonumber(target)
    resolvedName = target
else
    if not Network.lookup then
        io.stderr:write("ping: cannot resolve '" .. target .. "' (no lookup)\n")
        return 1
    end
    targetID = Network.lookup(target)
    if not targetID then
        c(colors.red, function()
            io.stderr:write("ping: " .. target .. ": Name or service not known\n")
        end)
        return 1
    end
    resolvedName = target
end

if not Network.ping then
    io.stderr:write("ping: Network.ping() not available\n")
    return 1
end

print("PING " .. resolvedName .. " (" .. tostring(targetID) .. ") 56 data bytes")

local sent = 0
local recv = 0
local totalRtt = 0
local minRtt, maxRtt

for n = 1, count do
    sent = sent + 1
    local rtt, err = Network.ping(targetID)
    if rtt then
        recv = recv + 1
        local ms = rtt * 1000
        totalRtt = totalRtt + ms
        if not minRtt or ms < minRtt then minRtt = ms end
        if not maxRtt or ms > maxRtt then maxRtt = ms end
        print(string.format("64 bytes from %s: icmp_seq=%d ttl=64 time=%.2f ms",
            resolvedName, n, ms))
    else
        c(colors.red, function()
            print("ping: " .. resolvedName .. ": Destination Host Unreachable")
        end)
    end
    if n < count then os.sleep(1) end
end

-- Summary
local loss = sent > 0 and math.floor(((sent - recv) / sent) * 100) or 0
local avg = recv > 0 and (totalRtt / recv) or 0
print("")
print(string.format("--- %s ping statistics ---", resolvedName))
print(string.format("%d packets transmitted, %d received, %d%% packet loss",
    sent, recv, loss))
if recv > 0 then
    print(string.format("rtt min/avg/max = %.2f/%.2f/%.2f ms",
        minRtt or 0, avg, maxRtt or 0))
end

return recv > 0 and 0 or 1
