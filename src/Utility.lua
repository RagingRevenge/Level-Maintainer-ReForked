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

function logInfo(message)
    if type(message) == "string" then
        print("[" .. timestamp() .. "] " .. message)
    end
end