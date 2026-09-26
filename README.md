# Infinite Maintainer

Lets you passive lines easily, without lag and randomness of AE2 maintainer.
Also supports having a threshold.

# Setup

- Full block ME interface connected to an adapter
- Crafting Monitors on your CPUs
- (Internet card)
- OC stuff to make a basic computer

# Installation

Download it

```bash
wget raw.githubusercontent.com/Echoloquate/Level-Maintainer/master/installer.lua && installer
```

Run it

```bash
Maintainer
```

# Config

You can change maintained items in `config.lua`. There are two blocks: `cfg.items` for regular items (and the legacy `ae2fc:fluid_drop` workaround) and `cfg.fluids` for native fluid maintenance on GTNH 2.9+.

## Items

```lua
cfg["items"] = {
    ["Osmium Dust"] = {nil, 64},                                  -- no threshold
    ["drop of Molten SpaceTime"] = {1000000, 1, "spacetime"},     -- fluid drop with threshold + fluid name
}
```

Pattern: `["item_label"] = {threshold, batch_size, fluid_name?}`. The third value is only needed for `ae2fc:fluid_drop` items and is the fluid's registry name -- this path works on any GTNH version.

## Fluids (GTNH 2.9+)

GTNH 2.9 unified items and fluids in the OpenComputers AE2 integration, so fluid craftables can now be requested directly without going through `ae2fc:fluid_drop`. Threshold checks use real fluid amounts in mB.

```lua
cfg["fluids"] = {
    ["Molten SpaceTime"] = {1000000, 1000},
}
```

Pattern: `["fluid_label"] = {threshold_mb, batch_mb[, fluid_registry_name]}`. The label is the fluid's display name as shown in the AE crafting terminal. The fluid registry name is auto-detected from the craftable's stack -- pass it as a third value only as an override if auto-detection ever resolves to the wrong fluid. Omit the block entirely on pre-2.9 setups.

## Settings

Timing and behaviour live in `settings.lua` (anything missing falls back to a default):

| Setting | Default | What it does |
|---|---|---|
| `sleep` | `10` | Seconds between cycles. |
| `retryDelay` | `60` | Seconds to wait before recalculating an entry whose request failed (missing ingredients, no suitable CPU). `0` retries every cycle. |
| `requireFreeCpu` | `true` | Only start a calculation when a crafting CPU (or `cpuName`) is idle. |
| `cpuName` | `nil` | Send every request to this named crafting CPU. `nil` lets AE2 pick. |
| `cacheDuration` | `600` | Seconds craftable lookups are cached. New patterns are picked up after at most this long. |
| `pollInterval` | `1` | Seconds between checks while AE2 calculates a request. |
| `logSkips` | `true` | Log entries skipped for being in progress, stocked, waiting to retry or waiting for a CPU. |

**!! Threshold has a performance impact -- only add it when necessary, and preferably not on mainnet !!**

Reboot after changing values.
