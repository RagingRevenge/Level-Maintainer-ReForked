local shell = require("shell")
local filesystem = require("filesystem")
local component = require("component")
local scripts = {"src/AE2.lua", "src/Utility.lua", "Maintainer.lua"}

local paths = {"src", "lib"}

local function exists(filename)
    return filesystem.exists(shell.getWorkingDirectory() .. "/" .. filename)
end

local repo = "https://raw.githubusercontent.com/Willshaper/Level-Maintainer/";
local branch = "master"

for i = 1, #paths do
    if not filesystem.exists(shell.getWorkingDirectory() .. "/" .. paths[i]) then
        filesystem.makeDirectory(shell.getWorkingDirectory() .. "/" .. paths[i]);
    end
end

for i = 1, #scripts do
    if exists(scripts[i]) then
        filesystem.remove(shell.getWorkingDirectory() .. "/" .. scripts[i]);
    end

    shell.execute(string.format("wget %s%s/%s %s", repo, branch, scripts[i], scripts[i]));
end

for _, file in ipairs({"config.lua", "settings.lua"}) do
    if not exists(file) then
        shell.execute(string.format("wget %s%s/%s %s", repo, branch, file, file));
    end
end

local function ask(question)
    io.write(question .. " [y/N] ")
    local answer = io.read()
    return answer ~= nil and answer:lower():sub(1, 1) == "y"
end

-- Auto-start: OpenOS runs every line of /home/.shrc when the shell starts
local shrc = (os.getenv("HOME") or "/home") .. "/.shrc"
local function autostartEnabled()
    local file = io.open(shrc, "r")
    if not file then
        return false
    end
    local content = file:read("*a")
    file:close()
    return content:find("Maintainer", 1, true) ~= nil
end

print()
if autostartEnabled() then
    print("Auto-start is already on (" .. shrc .. "). Delete the Maintainer line there to turn it off.")
elseif ask("Start Maintainer automatically when the computer boots?") then
    local file = io.open(shrc, "a")
    file:write(string.format('cd "%s" && Maintainer\n', shell.getWorkingDirectory()))
    file:close()
    print("Auto-start on. Delete the Maintainer line in " .. shrc .. " to turn it off.")
end

-- Wake-on-redstone: with a redstone card, a rising redstone signal turns the computer on
-- (a running computer ignores it), so a slow redstone clock restarts it after a power loss
if component.isAvailable("redstone") then
    local redstone = component.redstone
    if redstone.getWakeThreshold() > 0 then
        print("Wake-on-redstone is already on (threshold " .. redstone.getWakeThreshold() .. ").")
    elseif ask("Turn the computer on when it receives a redstone signal (for a watchdog clock)?") then
        redstone.setWakeThreshold(1)
        print("Wake-on-redstone on. A redstone pulse into the computer now starts it if it is off.")
    end
end

print("Rebooting...")
os.sleep(2)
shell.execute("reboot");