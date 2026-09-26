local component = require("component")
local computer = require("computer")
local ME = component.me_interface

local AE2 = {}

-- Lightweight cache for specific items only.
-- Values: a craftable userdata (hit), or `false` (negative lookup).
local itemCache = {}
local fluidNameCache = {} -- name -> fluid registry name, or false if the craftable has no fluid stack
local cacheTimestamp = 0

-- Overridden from settings.lua via AE2.configure()
local cacheDuration = 600
local pollInterval = 1
local cpuName = nil

function AE2.configure(settings)
    cacheDuration = settings.cacheDuration
    pollInterval = settings.pollInterval
    cpuName = settings.cpuName
end

-- Starts a crafting calculation and waits for it to finish.
-- Returns true, or false plus AE2's failure reason.
local function submit(craftable, count)
    local craft
    if cpuName then
        craft = craftable.request(count, true, cpuName)
    else
        craft = craftable.request(count)
    end

    while craft.isComputing() == true do
        os.sleep(pollInterval)
    end
    local failed, reason = craft.hasFailed()
    return not failed, reason
end

-- getStack() of a fluid craftable has "amount" and no "damage"; item stacks always have "damage"
local function isFluidStack(stack)
    return stack ~= nil and stack.damage == nil and stack.amount ~= nil
end

-- Function to get or cache a specific craftable item
local function getCraftableForItem(itemName)
    local currentTime = computer.uptime() -- real seconds; os.time() is in-game time (72x faster)

    local cached = itemCache[itemName]
    if cached ~= nil and currentTime - cacheTimestamp < cacheDuration then
        if cached == false then return nil end
        return cached
    end

    -- If cache is too old, clear it completely to save memory
    if currentTime - cacheTimestamp >= cacheDuration then
        itemCache = {}
        fluidNameCache = {}
        cacheTimestamp = currentTime
    end

    -- Look for this specific item in craftables
    local craftables = ME.getCraftables({["label"] = itemName})
    if #craftables >= 1 then
        itemCache[itemName] = craftables[1] -- Cache only this one item
        return craftables[1]
    end

    itemCache[itemName] = false -- Cache the negative lookup so misspelled entries don't re-query every cycle
    return nil
end

function AE2.requestItem(name, threshold, count, fluidName)
    local craftable = getCraftableForItem(name)

    if craftable then
        local item = (craftable.getStack or craftable.getItemStack)(craftable)
        -- A fluid listed under cfg.items: check its stock as a fluid, not as an item
        if isFluidStack(item) then
            return AE2.requestFluid(name, threshold, count)
        end
        if threshold ~= nil then
            local itemInSystem = nil
            
            if fluidName then
                local fluidTag = '{Fluid:' .. fluidName .. '}'
                itemInSystem = ME.getItemInNetwork("ae2fc:fluid_drop", 0, fluidTag)
            else
                if item.name then
                    -- item.tag is gzipped binary NBT, not the SNBT string the 3-arg form expects.
                    -- Newer OC accepts the stack table itself and decodes the tag; older OC
                    -- rejects a table, so fall back to name + damage (ignores NBT).
                    local ok, result = pcall(ME.getItemInNetwork, item)
                    if ok then
                        itemInSystem = result
                    else
                        itemInSystem = ME.getItemInNetwork(item.name, item.damage or 0)
                    end
                end
            end
            
            if itemInSystem ~= nil and itemInSystem.size >= threshold then 
                return table.unpack({false, "The amount of " .. (itemInSystem.label or name) .. " (" .. itemInSystem.size .. ") meets or exceeds threshold (" .. threshold .. ")! Aborting request.", "stocked"})
            end
        end
        
        if item.label == name then
            local ok, reason = submit(craftable, count)
            if not ok then
                return table.unpack({false, "Failed to request " .. name .. " x " .. count .. " (" .. tostring(reason) .. ")", "failed"})
            else
                return table.unpack({true, "Requested " .. name .. " x " .. count, "requested"})
            end
        end
    end
    return table.unpack({false, name .. " is not craftable!", "missing"})
end

-- Native fluid maintenance via getFluidInNetwork (GTNH 2.9+).
-- `name` is the fluid craftable label; `fluidName` is the fluid registry name and is
-- auto-detected from the craftable's stack if omitted (pass it only as an override).
function AE2.requestFluid(name, threshold, count, fluidName)
    local craftable = getCraftableForItem(name)

    if craftable then
        if threshold ~= nil then
            if not fluidName then
                local cached = fluidNameCache[name]
                if cached == nil then
                    local stack = (craftable.getStack or craftable.getItemStack)(craftable)
                    cached = (isFluidStack(stack) and stack.name) or false
                    fluidNameCache[name] = cached
                end
                -- An item listed under cfg.fluids: check its stock as an item
                if not cached then
                    return AE2.requestItem(name, threshold, count)
                end
                fluidName = cached
            end

            if fluidName and ME.getFluidInNetwork then
                local fluidInSystem = ME.getFluidInNetwork(fluidName)
                local amount = fluidInSystem and (fluidInSystem.size or fluidInSystem.amount)
                if amount and amount >= threshold then
                    return table.unpack({false, "The amount of " .. (fluidInSystem.label or name) .. " (" .. amount .. " mB) meets or exceeds threshold (" .. threshold .. " mB)! Aborting request.", "stocked"})
                end
            end
        end

        local ok, reason = submit(craftable, count)
        if not ok then
            return table.unpack({false, "Failed to request " .. name .. " x " .. count .. " mB (" .. tostring(reason) .. ")", "failed"})
        else
            return table.unpack({true, "Requested " .. name .. " x " .. count .. " mB", "requested"})
        end
    end
    return table.unpack({false, name .. " is not craftable!", "missing"})
end

-- Returns: set of labels currently being crafted, number of idle CPUs,
-- and a name -> busy map of all CPUs.
function AE2.checkIfCrafting()
    local cpus = ME.getCpus()
    local items = {}
    local freeCpus = 0
    local cpuBusy = {}
    for k, v in pairs(cpus) do
        local finaloutput = v.cpu.finalOutput()
        if finaloutput ~= nil then
            items[finaloutput.label] = true
        end
        if not v.busy then
            freeCpus = freeCpus + 1
        end
        -- First CPU with a given name wins, matching how request() picks by name
        if v.name and cpuBusy[v.name] == nil then
            cpuBusy[v.name] = v.busy
        end
    end

    return items, freeCpus, cpuBusy
end

-- Returns true if the ME interface exposes the GTNH 2.9+ native fluid API.
function AE2.hasFluidSupport()
    return ME.getFluidInNetwork ~= nil
end

-- Function to manually clear the cache if needed
function AE2.clearCache()
    -- Re-resolve the interface in case the adapter/interface was replaced
    if component.isAvailable("me_interface") then
        ME = component.me_interface
    end
    itemCache = {}
    fluidNameCache = {}
    cacheTimestamp = 0
end

return AE2