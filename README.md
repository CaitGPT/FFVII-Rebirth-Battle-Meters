# Battle Meters — FF7 Rebirth combat meters

A small panel showing how your fight is going, in any battle. Press **Ctrl+Shift+D** to step through:

| Press | Shows |
| --- | --- |
| 1st | **DPS**: damage per second |
| 2nd | **HPS**: healing per second, MP spent and healing per MP |
| 3rd | **DTPS**: damage taken per second |
| 4th | Off |

HPS and DTPS also have a coloured line, split by party member: who received the healing, and who took the damage. DTPS
also lists each party member on their own row. Each battle
starts from zero. The last numbers stay on screen for 8 seconds afterwards.

With the optional **Battle Meters Native** mod, DPS and HPS show each party member on their own row, with the line split by who
dealt the damage and who did the healing. Each character is credited only the HP their hits really took or healed, and anything
no hit explains (poison, Regen) shows as Unattributed. Battle Meters Native is built for **UE4SS 3.0.1** only.

It only reads the game and draws a panel. It doesn't change damage, HP, MP or anything else, and it doesn't touch your saves.

This mod was built, tested and played by an AI (Claude Opus 5.5 in Claude Code), with a human setting the direction. It's part
of a bigger goal: teaching an agent to play the game, so that mods can be researched, built and tested end to end.

- Download it from [Nexus Mods](https://www.nexusmods.com/finalfantasy7rebirth/mods/2479).
- The video, showing the mod and then how it was built: [YouTube](https://www.youtube.com/watch?v=D6B8tCoiDWA).
- How to install and use it: [docs/GUIDE.md](docs/GUIDE.md).
- How we built it, step by step: [docs/HOW-WE-BUILT-IT.md](docs/HOW-WE-BUILT-IT.md).
- The design in reference form, what was tested and the limits: [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

## Install

Needs UE4SS v3 for FF7 Rebirth.

1. Copy the `BattleMeters` folder into `End/Binaries/Win64/ue4ss/Mods/`.
2. Add `BattleMeters : 1` to `mods.txt` in that folder, above the `Keybinds` line.
3. Optional, for damage and healing by character on UE4SS 3.0.1: copy the `BattleMetersNative` folder there too, and add
   `BattleMetersNative : 1` above the `BattleMeters` line. On another UE4SS version, leave it out: Battle Meters works as
   before, with totals only.

Or, from this repository: `tools/Install-BattleMeters.ps1 -Mode Install -GameRoot "<your game folder>"`, with `-WithNative` for
Battle Meters Native (build it first with `native/Build.ps1`). `-Mode Uninstall` and `-Mode Status` also exist.

It starts switched off, so nothing shows until you press the key.

It works alongside [Training Dummy](https://github.com/CaitGPT/FFVII-Rebirth-Training-Dummy): on that mod's courses, only
its panel shows.

## Known limits

- Any rise in HP counts as healing, including potions, Regen, HP Absorb and abilities that heal without MP. Overhealing adds nothing.
- MP spent is every MP the party spends, on any spell, so healing per MP only shows true healing efficiency if healing is all you spend MP on.
- Damage and healing on the same character within the same fifth of a second cancel out, so HPS and DTPS can read slightly low in busy moments.
- Boss fights haven't been tested.

The full list is in the [guide](docs/GUIDE.md#known-limits).

## Tests

`python -m pip install lupa`, then `python tests/run_tests.py`.

Battle Meters Native is C++ in `native/`. `native/Build.ps1` builds it against the pinned UE4SS 3.0.1 sources; see
[native/README.md](native/README.md).

## Credits

- UE4SS, FModel and the OpenFF7R community
- The panel comes from our Training Dummy mod and uses the game's own HUD art, loaded from your copy of the game

This repository contains no game files.

## Licence

MIT (see `LICENSE`).
