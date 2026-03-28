# PPBuddy

A companion addon for **PallyPowerTW** (WoW 1.12 / TurtleWoW).

Shows a draggable mini-bar listing every paladin blessing assigned to your class, color-coded so you can instantly see what you have, what you're missing, and who to ask.

## Requirements

- **PallyPowerTW** must be installed and loaded. PPBuddy reads its shared globals (`PallyPower_Assignments`, etc.) — no code changes to PallyPowerTW are needed.

## Features

| Feature | Detail |
|---|---|
| **Live buff status** | Scans your buffs every 2 s; green = have it, red = missing |
| **Assigned paladin name** | Shows which paladin is responsible when a buff is missing |
| **Whisper on click** | Click a **red (missing) row** to whisper the assigned paladin a polite request |
| **Ban checkbox** | Check the **X box** on any row to ban that buff — it is auto-removed whenever applied to you (same mechanic as LazyPig's Salvation Remover) |
| **Draggable** | Drag the frame anywhere; position is saved across sessions |

## Installation

1. Drop the `PPBuddy` folder into `Interface/AddOns/`.
2. Make sure `PallyPowerTW` is also installed and enabled.
3. Reload UI or log in.

## Slash Commands

| Command | Effect |
|---|---|
| `/ppb` | Show help |
| `/ppb show` | Show the bar |
| `/ppb hide` | Hide the bar |
| `/ppb reset` | Reset position to default |
| `/ppb bans` | List currently banned blessings |
| `/ppb clearbans` | Remove all bans |

## How banning works

Ticking the **X** checkbox next to a blessing marks it as *banned*.  
On every `PLAYER_AURAS_CHANGED` event, PPBuddy scans your active buffs and calls `CancelPlayerBuff()` on any banned blessing it finds — identical to how LazyPig removes Salvation.  The ban persists across sessions via the `PPBuddy_Config` saved variable.

## Notes

- Works for any non-Paladin class. Paladins are already covered by PallyPowerTW's own BuffBar.
- Hunter Pets and Warriors share Class ID 0 in PallyPower — if you see a Warrior blessing it also applies to Hunter pets (vanilla behaviour).
- The frame updates every 2 seconds to match PallyPower's debounce window.
