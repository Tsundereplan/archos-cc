--[[
    kernel/events.lua  —  Event dispatcher / hooks
    ==============================================
    Provides a publish/subscribe mechanism for kernel-level events.
    Different from os.pullEvent: events here can be observed by multiple
    listeners simultaneously.

    IMPORTANT: cached in _G._ARCHOS_EVENTS so all callers share the
    same listener registry.

    Listeners:
      subscribe(eventType, callback)   -> listener id
      unsubscribe(id)
      dispatch(eventType, ...)         -> nil
      dispatchRaw(eventTable)          -> nil

    Used for:
      * Plug-and-Play peripheral attach/detach notifications
      * Disk insertion/ejection events
      * Network packet arrival
      * System shutdown signals
]]

-- Module cache
if _G._ARCHOS_EVENTS then
    return _G._ARCHOS_EVENTS
end

local Events = {}

local listeners = {}     -- eventType -> { {id=, cb=} }
local nextListenerId = 1
local catchAll = {}      -- listeners that get every event

function Events.subscribe(eventType, callback)
    if type(eventType) == "function" then
        -- catch-all subscription
        local id = nextListenerId
        nextListenerId = nextListenerId + 1
        table.insert(catchAll, { id = id, cb = eventType })
        return id
    end

    if not listeners[eventType] then
        listeners[eventType] = {}
    end
    local id = nextListenerId
    nextListenerId = nextListenerId + 1
    table.insert(listeners[eventType], { id = id, cb = callback })
    return id
end

function Events.unsubscribe(id)
    for eventType, lst in pairs(listeners) do
        for i = #lst, 1, -1 do
            if lst[i].id == id then table.remove(lst, i) end
        end
    end
    for i = #catchAll, 1, -1 do
        if catchAll[i].id == id then table.remove(catchAll, i) end
    end
end

function Events.dispatch(eventType, ...)
    local evt = listeners[eventType]
    if evt then
        for _, l in ipairs(evt) do
            local ok, err = pcall(l.cb, ...)
            if not ok then
                -- Log error but don't crash the dispatcher
                if _G.BIOS and _G.BIOS.log then
                    _G.BIOS.log("[events] listener error: " .. tostring(err))
                end
            end
        end
    end
    -- Catch-all listeners
    for _, l in ipairs(catchAll) do
        local ok, err = pcall(l.cb, eventType, ...)
        if not ok then
            if _G.BIOS and _G.BIOS.log then
                _G.BIOS.log("[events] catch-all error: " .. tostring(err))
            end
        end
    end
end

function Events.dispatchRaw(eventTable)
    Events.dispatch(eventTable[1], table.unpack(eventTable, 2))
end

-- Pre-defined event types
Events.TYPES = {
    PERIPHERAL_ATTACH   = "peripheral",
    PERIPHERAL_DETACH   = "peripheral_detach",
    DISK_INSERT         = "disk",
    DISK_EJECT          = "disk_eject",
    REDSTONE_CHANGE     = "redstone",
    MODEM_MESSAGE       = "modem_message",
    REDNET_MESSAGE      = "rednet_message",
    HTTP_SUCCESS        = "http_success",
    HTTP_FAILURE        = "http_failure",
    SHUTDOWN            = "archos_shutdown",
    REBOOT              = "archos_reboot",
    USER_LOGIN          = "archos_user_login",
    USER_LOGOUT         = "archos_user_logout",
    SERVICE_START       = "archos_service_start",
    SERVICE_STOP        = "archos_service_stop",
    FS_MOUNT            = "archos_fs_mount",
    FS_UMOUNT           = "archos_fs_umount",
    PACKAGE_INSTALL     = "archos_pkg_install",
    PACKAGE_REMOVE      = "archos_pkg_remove",
}

-- Cache the Events module.
_G._ARCHOS_EVENTS = Events
return Events
