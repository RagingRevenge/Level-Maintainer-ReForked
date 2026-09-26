local filesystem = require("filesystem")

local timeOffset = 0 -- seconds added to UTC for log timestamps
local CLOCK_FILE = "/tmp/.maintainer_clock"

function setTimeOffset(hours)
    timeOffset = (tonumber(hours) or 0) * 3600
end

-- OC has no real-time clock and os.date() uses in-game time. Opening a file
-- for writing stamps it with the server's real clock (UTC), so touch one in
-- /tmp and format its modification time instead.
local function timestamp()
    local file = io.open(CLOCK_FILE, "w")
    if file then
        file:close()
        local modified = filesystem.lastModified(CLOCK_FILE)
        if modified and modified > 0 then
            return os.date("%H:%M:%S", modified / 1000 + timeOffset)
        end
    end
    return os.date("%H:%M:%S") -- in-game time as a fallback
end

-- Current real time as HH:MM:SS
function currentTime()
    return timestamp()
end

local logHandler = nil

-- Sends log lines to handler(line) instead of printing them (nil = print again)
function setLogHandler(handler)
    logHandler = handler
end

function logInfo(message)
    if type(message) == "string" then
        local line = "[" .. timestamp() .. "] " .. message
        if logHandler then
            logHandler(line)
        else
            print(line)
        end
    end
end