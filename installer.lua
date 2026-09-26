local shell = require("shell")
local filesystem = require("filesystem")
local component = require("component")
local scripts = {"src/AE2.lua", "src/Display.lua", "src/Utility.lua", "Maintainer.lua"}

local repo = "https://raw.githubusercontent.com/Willshaper/Level-Maintainer/";
local branch = "master"
local dir = shell.getWorkingDirectory()

local function path(filename)
    return dir .. "/" .. filename
end

-- Files are downloaded to a temporary name first, and only put in place once every
-- download worked: a failed download (no internet card, GitHub down) leaves the
-- existing install untouched instead of a mix of old and new scripts.
-- (wget leaves an empty file behind when a download fails.)
local function temp(filename)
    return path(filename .. ".download")
end

local function download(filename)
    filesystem.remove(temp(filename))
    shell.execute(string.format("wget -f %s%s/%s %s", repo, branch, filename, temp(filename)))
    return filesystem.exists(temp(filename)) and filesystem.size(temp(filename)) > 0
end

if not filesystem.exists(path("src")) then
    filesystem.makeDirectory(path("src"))
end

local wanted = {}
for _, file in ipairs(scripts) do
    table.insert(wanted, file)
end
-- config.lua and settings.lua are yours; only fetched when missing
for _, file in ipairs({"config.lua", "settings.lua"}) do
    if not filesystem.exists(path(file)) then
        table.insert(wanted, file)
    end
end

local failed = {}
for _, file in ipairs(wanted) do
    if not download(file) then
        table.insert(failed, file)
    end
end

if #failed > 0 then
    for _, file in ipairs(wanted) do
        filesystem.remove(temp(file))
    end
    print()
    print("Could not download: " .. table.concat(failed, ", "))
    print("Nothing was changed. Check that the computer has an internet card and")
    print("try again. Not rebooting.")
    return
end

for _, file in ipairs(wanted) do
    filesystem.remove(path(file))
    filesystem.rename(temp(file), path(file))
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