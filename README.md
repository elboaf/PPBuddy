# PPBuddy

A compact blessing status bar for WoW 1.12 / TurtleWoW.

Shows your assigned paladin blessings as a small row of icons. At a glance you can see what you have, what you're missing, and click to ask for it.

## Requirements

**No dependencies.** PPBuddy listens directly to PallyPower's `PLPWR` addon channel messages, so it works as long as at least one paladin in your raid or party has PallyPowerTW installed — you don't need it yourself.

If you *do* have PallyPowerTW installed (e.g. as a raid leader), PPBuddy will also read its globals directly. Both modes work simultaneously with no conflict.

## Installation

Drop the `PPBuddy` folder into `Interface/AddOns/` and reload. That's it.

## The Bar

A small horizontal strip of blessing icons — one per buff assigned to your class. Drag it anywhere; position is saved across sessions. Auto-hides when no assignments are known yet.

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

Right-clicking an icon bans that blessing. PPBuddy will automatically cancel it via `CancelPlayerBuff()` whenever it is applied to you — the same mechanic LazyPig uses for Salvation removal. Bans persist across sessions.

## Saved Settings

Position and bans are both saved per-character across sessions via the `PPBuddy_Config` saved variable.

## Slash Commands

| Command | Effect |
|---|---|
| `/ppb show` | Show the bar |
| `/ppb hide` | Hide the bar |
| `/ppb reset` | Reset position to default |
| `/ppb bans` | List currently banned blessings |
| `/ppb clearbans` | Remove all bans |
| `/ppb debug` | Dump known assignment data to chat |

## Notes

- The bar auto-hides when no assignments are known yet (e.g. before any paladin has broadcast their data after a fresh login).
- Paladins already have PallyPowerTW's own BuffBar — PPBuddy is for everyone else.
- Hunter Pets and Warriors share Class ID 0 in PallyPower, so a Warrior blessing covers both (vanilla behaviour, not a bug).
