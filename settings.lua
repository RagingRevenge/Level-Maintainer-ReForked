local settings = {}

-- Maintainer behaviour. The list of maintained items lives in config.lua.
-- Changes are picked up automatically a few seconds after saving; no restart needed.

-- Seconds to wait between cycles. Each cycle checks every configured entry once.
settings.sleep = 10

-- After a crafting request fails (missing ingredients, no suitable CPU, ...),
-- wait this many seconds before calculating that entry again.
-- Other entries are unaffected. 0 = retry every cycle.
-- Also the pause before the maintainer restarts itself after an unexpected
-- error (at least 5 seconds).
settings.retryDelay = 60

-- Only start a calculation when a crafting CPU is idle (or the CPU named in
-- cpuName, if set). AE2 otherwise calculates the whole craft and then fails
-- to submit it.
settings.requireFreeCpu = true

-- Name of the crafting CPU to use for all requests, as named in AE2,
-- e.g. "Maintainer". nil = let AE2 pick any CPU.
settings.cpuName = nil

-- How long craftable lookups are cached, in seconds. Newly added patterns
-- (and fixed typos in config.lua) are picked up after at most this long.
settings.cacheDuration = 600

-- How often to check whether AE2 has finished calculating a request, in seconds.
settings.pollInterval = 1

-- Log entries that are skipped because they are already crafting, above
-- their threshold, waiting to retry, or waiting for a free CPU.
settings.logSkips = true

-- Repeat skip messages every cycle. false = log each entry's status once, and
-- again only when it changes (e.g. "meets or exceeds threshold" appears once
-- after a craft instead of every cycle).
settings.logRepeats = false

-- Hours to add to UTC for log timestamps, e.g. 1 for CET, 2 for CEST,
-- -5 for EST. Change it when daylight saving time starts or ends.
settings.utcOffset = 0

-- Live reload: how often, in seconds, to check whether config.lua or settings.lua
-- was saved while the maintainer runs, and reload them. Only useful if you can
-- edit the files outside the game (singleplayer, or a server on your own PC),
-- since the maintainer has to be stopped to use edit in game. e.g. 30.
-- 0 = off. The files are read fresh every time the maintainer starts either way.
settings.reloadCheck = 0

return settings
