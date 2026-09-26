local computer = require("computer")
local filesystem = require("filesystem")
local shell = require("shell")
local ae2 = require("src.AE2")
local util = require("src.Utility")

-- config.lua and settings.lua are read with loadfile rather than require (which caches
-- until reboot), and reloaded whenever they are saved. Found the same way require would.
local function findFile(module)
    local path = package.searchpath(module, package.path)
    return path and shell.resolve(path) or shell.resolve(module .. ".lua")
end
local CONFIG_PATH = findFile("config")
local SETTINGS_PATH = findFile("settings")
local RELOAD_CHECK = 2 -- seconds between checks for edited files while waiting

-- Runs a Lua file that returns a table. Returns the table, or nil and an error message.
local function loadTable(path)
    local chunk, err = loadfile(path)
    if not chunk then
        return nil, tostring(err)
    end
    local ok, result = pcall(chunk)
    if not ok then
        return nil, tostring(result)
    end
    if type(result) ~= "table" then
        return nil, path .. " does not end with a return statement"
    end
    return result
end

-- Defaults for anything missing from settings.lua (e.g. an older install without it)
local function buildSettings(userSettings, cfg)
    local s = {
        sleep = (cfg and cfg.sleep) or 10,
        retryDelay = 60,
        requireFreeCpu = true,
        cpuName = nil,
        cacheDuration = 600,
        pollInterval = 1,
        logSkips = true,
        logRepeats = false,
        utcOffset = 0,
    }
    for k, v in pairs(userSettings or {}) do
        s[k] = v
    end
    return s
end

local settings = buildSettings(nil, nil)
local userSettings = nil -- last successfully loaded settings.lua
local items, fluids = {}, nil
local configTime, settingsTime = nil, nil -- last-modified times of the loaded files

local function applySettings(cfg)
    settings = buildSettings(userSettings, cfg)
    ae2.configure(settings)
    setTimeOffset(settings.utcOffset)
end

local function loadSettings()
    settingsTime = filesystem.lastModified(SETTINGS_PATH)
    local loaded, err = loadTable(SETTINGS_PATH)
    if not loaded then
        return false, err
    end
    userSettings = loaded
    return true
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

local lastStatus = {} -- name -> status of the last message logged for that entry

-- Logs a status message for an entry. Unless logRepeats is on, the same status is
-- only logged once, until the entry's status changes.
local function logStatus(name, status, message)
    local repeated = lastStatus[name] == status
    lastStatus[name] = status
    if repeated and not settings.logRepeats then
        return
    end
    logInfo(message)
end

-- Skips (already crafting, stocked, waiting to retry, no CPU) are hidden entirely with logSkips = false
local function skip(name, status, message)
    if settings.logSkips then
        logStatus(name, status, message)
    else
        lastStatus[name] = status
    end
end

local retryAt = {} -- name -> uptime before which a failed entry is not calculated again
local lastConfig = nil -- config in use, to tell which entries changed on reload
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
        skip(name, "crafting", name .. " is already being crafted, skipping...")
    elseif retryAt[name] and now < retryAt[name] then
        skip(name, "retry", name .. " failed recently, retrying in " .. math.ceil(retryAt[name] - now) .. "s")
    elseif not cpuAvailable() then
        skip(name, "nocpu", name .. ": no free crafting CPU, skipping...")
    else
        local success, answer, result = try(request, name, config[1], config[2], config[3])
        if result == "stocked" then
            skip(name, "stocked", answer)
        elseif result == "missing" then
            logStatus(name, "missing", answer)
        elseif result == "failed" then
            retryAt[name] = computer.uptime() + settings.retryDelay
            if settings.retryDelay > 0 then
                answer = answer .. ", retrying in " .. settings.retryDelay .. "s"
            end
            -- Logged every time; the retry wait that follows is covered by this message
            logInfo(answer)
            lastStatus[name] = "retry"
        elseif result == "error" then
            lastStatus[name] = "error" -- already logged by try()
        else
            logInfo(answer)
            lastStatus[name] = result
        end

        if result ~= "failed" then
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

local function sameEntry(a, b)
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

-- Counts added, changed and removed entries between two configs, and forgets the
-- logged status and retry wait of every new or changed entry so its status is shown again.
local function describeChanges(old, new)
    local added, changed, removed = 0, 0, 0
    local function scan(oldBlock, newBlock)
        for name, conf in pairs(newBlock or {}) do
            local prev = oldBlock and oldBlock[name]
            if not prev then
                added = added + 1
            elseif not sameEntry(prev, conf) then
                changed = changed + 1
            end
            if not prev or not sameEntry(prev, conf) then
                lastStatus[name] = nil
                retryAt[name] = nil
            end
        end
        for name in pairs(oldBlock or {}) do
            if not (newBlock and newBlock[name]) then
                removed = removed + 1
            end
        end
    end
    scan(old and old.items, new.items)
    scan(old and old.fluids, new.fluids)
    return added .. " added, " .. changed .. " changed, " .. removed .. " removed"
end

local function applyConfig(cfg)
    items = cfg.items or {}
    fluids = cfg.fluids
    if fluids and next(fluids) ~= nil and not ae2.hasFluidSupport() then
        logInfo("WARNING: cfg.fluids is configured but the ME interface does not expose getFluidInNetwork (requires GTNH 2.9+). Fluid entries will be skipped.")
        fluids = nil
    end
    lastConfig = cfg
    applySettings(cfg) -- an old config.lua may still set cfg.sleep
end

-- Loads config.lua. Returns the table, or nil and the error. Remembers the file's
-- modification time either way, so a broken file is only reported once per save.
local function readConfig()
    configTime = filesystem.lastModified(CONFIG_PATH)
    return loadTable(CONFIG_PATH)
end

-- Reloads config.lua and settings.lua if they were saved since they were last read.
-- A file with a mistake is reported and the previous version stays in use.
-- Returns true if anything was reloaded.
local function reloadIfChanged()
    local reloaded = false
    if filesystem.lastModified(SETTINGS_PATH) ~= settingsTime then
        local ok, err = loadSettings()
        if ok then
            applySettings(lastConfig)
            logInfo("Reloaded settings.lua")
            reloaded = true
        else
            logInfo("ERROR: settings.lua has a mistake, keeping the previous settings: " .. err)
        end
    end
    if filesystem.lastModified(CONFIG_PATH) ~= configTime then
        local cfg, err = readConfig()
        if cfg then
            local summary = describeChanges(lastConfig, cfg)
            applyConfig(cfg)
            logInfo("Reloaded config.lua (" .. summary .. ")")
            reloaded = true
        else
            logInfo("ERROR: config.lua has a mistake, keeping the previous config: " .. err)
        end
    end
    return reloaded
end

-- Waits settings.sleep seconds, checking for edited files every few seconds.
-- An edit ends the wait early so the new config is used right away.
local function waitForNextCycle()
    local deadline = computer.uptime() + settings.sleep
    repeat
        os.sleep(math.max(0, math.min(RELOAD_CHECK, deadline - computer.uptime())))
        if reloadIfChanged() then
            return
        end
    until computer.uptime() >= deadline
end

local function run()
    while true do
        reloadIfChanged()

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

        waitForNextCycle()
    end
end

-- At boot the computer can start before the adapter/interface is ready, so wait for it
local function waitForInterface()
    if ae2.connect() then
        return
    end
    logInfo("Waiting for an ME interface (adapter touching a full-block ME interface)...")
    repeat
        os.sleep(5)
    until ae2.connect()
    logInfo("ME interface found.")
end

-- At startup a broken config.lua is reported and the maintainer waits for it to be fixed
local function loadInitialConfig()
    local cfg, err = readConfig()
    if not cfg then
        logInfo("ERROR: config.lua has a mistake: " .. err)
        logInfo("Fix and save it; the maintainer starts as soon as it loads.")
        repeat
            os.sleep(RELOAD_CHECK)
            if filesystem.lastModified(CONFIG_PATH) ~= configTime then
                cfg, err = readConfig()
                if not cfg then
                    logInfo("ERROR: config.lua still has a mistake: " .. err)
                end
            end
        until cfg
        logInfo("config.lua loaded.")
    end
    applyConfig(cfg)
end

local function main()
    local ok, err = loadSettings()
    if not ok then
        logInfo("WARNING: could not load settings.lua, using defaults (" .. err .. ")")
    end
    applySettings(nil)

    waitForInterface()
    loadInitialConfig()

    -- run() only ends by an error. Anything other than Ctrl+Alt+C is logged and the
    -- loop restarts after a pause, so one unexpected error doesn't stop maintenance.
    while true do
        local _, err = pcall(run)
        if err == "interrupted" then
            error(err, 0)
        end
        local delay = math.max(tonumber(settings.retryDelay) or 0, 5)
        logInfo("ERROR: " .. tostring(err))
        logInfo("Restarting in " .. delay .. "s...")
        ae2.clearCache()
        os.sleep(delay)
    end
end

-- Ctrl+Alt+C raises "interrupted" from inside os.sleep. Exit quietly instead
-- of letting OpenOS print it as an error with a stack trace.
local ok, err = xpcall(main, function(msg)
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
