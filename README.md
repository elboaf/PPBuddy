# PPBuddy

A companion addon for **PallyPowerTW** (WoW 1.12 / TurtleWoW).

Shows a compact icon bar listing every paladin blessing assigned to your class. At a glance you can see what you have, what you're missing, and click to ask for it.

## Requirements

**PallyPowerTW must be installed and loaded.** PPBuddy reads PP's shared globals (`PallyPower_Assignments`, etc.) to know which blessings are assigned to your class and by whom. It requires no changes to PallyPowerTW itself.

## Installation

Drop the `PPBuddy` folder into `Interface/AddOns/` alongside PallyPowerTW and reload.

## The Bar

A small horizontal strip of blessing icons — one per buff assigned to your class. Nothing else. Drag it anywhere to reposition; location is saved across sessions.

| Border colour | Meaning |
|---|---|
| 🟢 Green | You have this buff |
| 🔴 Red | Missing |
| ⬛ Grey + dimmed | Banned (auto-removed) |

## Controls

| Input | Action |
|---|---|
| **Hover** | Tooltip shows buff name, assigned paladin, and available actions |
| **Left-click** a red icon | Whispers the assigned paladin asking for the buff |
| **Right-click** any icon | Toggles ban on that buff |

## Banning a Buff

Right-clicking an icon bans that blessing — PPBuddy will automatically cancel it via `CancelPlayerBuff()` whenever it's applied to you, on every `PLAYER_AURAS_CHANGED` event. Same mechanic LazyPig uses for Salvation removal. Bans persist across sessions.

## Slash Commands

| Command | Effect |
|---|---|
| `/ppb show` | Show the bar |
| `/ppb hide` | Hide the bar |
| `/ppb reset` | Reset position to default |
| `/ppb bans` | List currently banned blessings |
| `/ppb clearbans` | Remove all bans |
| `/ppb debug` | Dump raw PallyPower assignment data to chat |

## Notes

- The bar auto-hides when PP has no assignments for your class yet.
- Paladins already have PP's own BuffBar — PPBuddy is for everyone else.
- Hunter Pets and Warriors share Class ID 0 in PallyPower, so a Warrior blessing covers both (vanilla behaviour, not a bug).
