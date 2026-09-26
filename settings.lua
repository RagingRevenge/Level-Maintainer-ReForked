local settings = {}

-- Maintainer behaviour. The list of maintained items lives in config.lua.
-- Reboot after changing values.

-- Seconds to wait between cycles. Each cycle checks every configured entry once.
settings.sleep = 10

-- After a crafting request fails (missing ingredients, no suitable CPU, ...),
-- wait this many seconds before calculating that entry again.
-- Other entries are unaffected. 0 = retry every cycle.
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

-- Hours to add to UTC for log timestamps, e.g. 1 for CET, 2 for CEST,
-- -5 for EST. Change it when daylight saving time starts or ends.
settings.utcOffset = 0

return settings
