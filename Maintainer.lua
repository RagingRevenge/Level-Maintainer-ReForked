local computer = require("computer")
local ae2 = require("src.AE2")
local cfg = require("config")
local util = require("src.Utility") 

-- Defaults for anything missing from settings.lua (e.g. an older install without it)
local settings = {
    sleep = cfg.sleep or 10,
    retryDelay = 60,
    requireFreeCpu = true,
    cpuName = nil,
    cacheDuration = 600,
    pollInterval = 1,
    logSkips = true,
    utcOffset = 0,
}
local loaded, userSettings = pcall(require, "settings")
if loaded and type(userSettings) == "table" then
    for k, v in pairs(userSettings) do
        settings[k] = v
    end
else
    logInfo("WARNING: could not load settings.lua, using defaults (" .. tostring(userSettings) .. ")")
end
ae2.configure(settings)
setTimeOffset(settings.utcOffset)

local items = cfg.items
local fluids = cfg.fluids

if fluids and next(fluids) ~= nil and not ae2.hasFluidSupport() then
    logInfo("WARNING: cfg.fluids is configured but the ME interface does not expose getFluidInNetwork (requires GTNH 2.9+). Fluid entries will be skipped.")
    fluids = nil
end

-- Runs fn protected so a component error (interface removed, stale craftable, ...)
-- is logged and retried next cycle instead of killing the maintainer.
local function try(fn, ...)
    local ok, success, answer, result = pcall(fn, ...)
    if not ok then
        -- Ctrl+Alt+C raises "interrupted" from inside os.sleep; let it stop the script
        if success == "interrupted" then
            error(success, 0)
        end
        logInfo("ERROR: " .. tostring(success))
        ae2.clearCache()
        return false, nil, "error"
    end
    return success, answer, result
end

local function skip(message)
    if settings.logSkips then
        logInfo(message)
    end
end

local retryAt = {} -- name -> uptime before which a failed entry is not calculated again
local warnedCpuName = false

-- Refreshed at the start of every cycle
local itemsCrafting, freeCpus, cpuBusy = {}, 0, {}
local useNamedCpu = false

local function cpuAvailable()
    if not settings.requireFreeCpu then
        return true
    end
    if useNamedCpu then
        return not cpuBusy[settings.cpuName]
    end
    return freeCpus > 0
end

local function maintain(name, config, request)
    local now = computer.uptime()
    if itemsCrafting[name] == true then
        skip(name .. " is already being crafted, skipping...")
    elseif retryAt[name] and now < retryAt[name] then
        skip(name .. " failed recently, retrying in " .. math.ceil(retryAt[name] - now) .. "s")
    elseif not cpuAvailable() then
        skip(name .. ": no free crafting CPU, skipping...")
    else
        local success, answer, result = try(request, name, config[1], config[2], config[3])
        if result == "stocked" then
            skip(answer)
        else
            logInfo(answer)
        end

        if result == "failed" then
            retryAt[name] = computer.uptime() + settings.retryDelay
        else
            retryAt[name] = nil
        end

        -- The job now occupies a CPU for the rest of this cycle
        if success then
            freeCpus = freeCpus - 1
            if useNamedCpu then
                cpuBusy[settings.cpuName] = true
            end
        end
    end
end

local function run()
    while true do
        local ok
        ok, itemsCrafting, freeCpus, cpuBusy = pcall(ae2.checkIfCrafting)
        if not ok then
            logInfo("ERROR: " .. tostring(itemsCrafting))
            ae2.clearCache()
            itemsCrafting, freeCpus, cpuBusy = {}, 0, {}
        end

        useNamedCpu = settings.cpuName ~= nil and cpuBusy[settings.cpuName] ~= nil
        if ok and settings.cpuName ~= nil and not useNamedCpu and not warnedCpuName then
            logInfo("WARNING: no crafting CPU named '" .. settings.cpuName .. "' found, AE2 will use any CPU.")
            warnedCpuName = true
        end

        for item, config in pairs(items) do
            maintain(item, config, ae2.requestItem)
        end

        if fluids then
            for fluid, config in pairs(fluids) do
                maintain(fluid, config, ae2.requestFluid)
            end
        end

        os.sleep(settings.sleep)
    end
end

-- Ctrl+Alt+C raises "interrupted" from inside os.sleep. Exit quietly instead
-- of letting OpenOS print it as an error with a stack trace.
local ok, err = xpcall(run, function(msg)
    if msg == "interrupted" then
        return msg
    end
    return debug.traceback(tostring(msg), 2)
end)
if not ok then
    if err == "interrupted" then
        logInfo("Maintainer stopped.")
    else
        error(err, 0)
    end
end
