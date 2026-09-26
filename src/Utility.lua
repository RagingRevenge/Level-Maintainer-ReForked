local filesystem = require("filesystem")

function dump(o, depth)
    if depth == nil then depth = 0 end

    if depth > 10 then return "..." end

    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"' .. k .. '"' end
            s = s .. '[' .. k .. '] = ' .. dump(v, depth + 1) .. ',\n'
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

function parser(string)
    if type(string) == "string" then
        local numberString = string.gsub(string, "([^0-9]+)", "")
        if tonumber(numberString) then
            return math.floor(tonumber(numberString) + 0)
        end
        return 0
    else
        return 0
    end
end

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

function logInfo(string)
    if type(string) == "string" then
        print("[" .. timestamp() .. "] " .. string)
    end
end