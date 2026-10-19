-- /sbin/networkd.lua  —  Network daemon
-- Continuously monitors network state, handles DHCP-like announcement,
-- maintains host table, processes incoming packets.

local Network = _G.Network or (fs.exists("/lib/network.lua") and dofile("/lib/network.lua"))
local Events = _G.Events

if not Network then
    print("networkd: network library not available")
    return 1
end

print("[networkd] Starting network daemon ...")
Network.init()
print("[networkd] Online as: " .. Network.hostname .. " (channel " .. Network.channel .. ")")

-- Main loop: process incoming packets and route them
while true do
    local packet = Network.receive(5)
    if packet then
        local ptype = packet.type
        if ptype == "HELLO" then
            -- A new host announced itself
            if packet.hostname then
                Network.hosts[packet.hostname] = packet.from
            end
            if Events then Events.dispatch("archos_net_host_seen", packet) end
        elseif ptype == "LOOKUP" then
            -- Someone is asking for our hostname
            if packet.data and packet.data.hostname == Network.hostname then
                Network.send(packet.from, {
                    type = "RESPONSE",
                    from = os.getComputerID(),
                    hostname = Network.hostname,
                    data = { hostname = Network.hostname, id = os.getComputerID() },
                })
            end
        elseif ptype == "PING" then
            -- Respond with PONG
            Network.send(packet.from, {
                type = "PONG",
                from = os.getComputerID(),
                hostname = Network.hostname,
            })
        elseif ptype == "PONG" then
            -- Already handled by Network.ping()
        elseif ptype == "MSG" then
            if Events then Events.dispatch("archos_net_msg", packet) end
        end
    end
end
