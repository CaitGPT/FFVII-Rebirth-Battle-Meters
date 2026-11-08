# Battle Meters — how it works

The design in reference form. For the story, see [HOW-WE-BUILT-IT.md](HOW-WE-BUILT-IT.md). To install and play, see
[GUIDE.md](GUIDE.md).

## Overview

It's a UE4SS Lua mod with no data pak, so it replaces no game files. It reads HP and MP from the game's battle APIs, works out rates,
and draws a UMG panel built at runtime. It writes nothing to the game.

| File | Job | Calls the game? |
| --- | --- | --- |
| `main.lua` | The loop: finds the battle, reads HP and MP, handles the key | Yes |
| `overlay.lua` | Builds and draws the panel | Yes |
| `meters.lua` | Totals, rates, the rolling window, the killing-blow rule | No |
| `meter_view.lua` | What the panel shows, including each character's colour | No |
| `settings.lua` | Remembers the chosen meter in `settings.txt` | No |
| `config.lua` | Settings | No |

The pure files have offline tests in `tests/`.

## The loop

UE4SS `LoopAsync` runs every 200 ms and hands work to the game thread with `ExecuteInGameThread`. Each of those calls allocates a Lua
thread that UE4SS never frees, so outside a fight it only goes to the game thread once a second.

Battle functions are called only after a save has loaded (a party character or vehicle pawn has been seen), because calling them from
the title screen has crashed this game. During a battle the controller has no pawn, so a missing pawn only counts as leaving play after
two minutes outside a battle.

`pcall(ExecuteInGameThread, function() end)` runs while the mod loads. Each mod's first call adds a callback to UE4SS's process-event
list, and doing that during play can move the list under a running callback.

## What it reads

| Value | From |
| --- | --- |
| In a battle | `EndBattleAPI:IsInBattle` |
| Enemies | `EndBattleAPI:GetEnemyMembersRef` |
| HP and max HP | `EndBattleAPI:GetCharaHP`, `GetHPMax` |
| Party | `EndPartyAPI:GetBattleMemberCount`, `GetBattleMember`, `GetBattleMemberType` |
| MP | `EndMenuBPAPI:BPGetPlayerMP` |
| Time | `GameplayStatics:GetTimeSeconds` |
| Paused | `GameplayStatics:IsGamePaused` |

A fall in an enemy's HP is damage. A fall in a party member's HP is damage taken, and a rise is healing. A fall in MP is MP spent. The
first reading of anyone is only a baseline.

Enemies are told apart by address, so no game object is held between ticks.

### Killing blows

An enemy can die and leave the list between two reads, taking its last HP with it.

- **It leaves during the fight:** its last known HP counts as damage.
- **All enemies are gone when the battle ends:** that could be a kill, giving up or a wipe. Its HP counts only if it was at half HP or
  less when last read.
- **Enemies still listed when the battle ends** are taken to be alive, so nothing is added.

### Battle boundaries

A battle starts when `IsInBattle` is true with at least one enemy listed. It must stay false for 2 seconds to count as over, so a moment
between waves doesn't end it. Meters reset at the start of the next battle.

## The panel

Plain UMG widgets built at runtime: `Image` with the game's `U_Status_Base_01` sprite, and `TextBlock` in Roboto. The game's own
`EndTextBlock` and `EndImage` draw nothing when created at runtime. All widgets are made once, and only those that changed are updated,
since each setter is a reflected call on the game thread.

It sits at (48, 240) in 1920x1080 units: below the objective list a Combat Assignment shows in the top left, and above the combat help.
A level change takes it off the screen without destroying it, so `IsInViewport` decides when to rebuild it.

## Training Dummy

Battle Meters checks each new enemy's territory. In `terVR_COL30_SUMMON_Gilgamesh_010_BtlTest_Hard`, the one Training Dummy's courses use,
it hides its panel for that battle and adds no killing blow.

## Why there's no Settings menu entry

The Gameplay rows live in `UEndMainOptionsMenu._OptionItems`, a `TMap`. This UE4SS build logs `Property type 'MapProperty' not supported`
and aborts the whole chunk, even inside `pcall`, so Lua can't read or change it. Changing the widget's asset needs tooling we don't have
for this game: `retoc` fails on its container headers. Each row is also tied to a native `EOptionCategory`.

## Damage and healing by character (Battle Meters Native)

Requested in [issue 1](https://github.com/CaitGPT/FFVII-Rebirth-Battle-Meters/issues/1). The game reports every hit and heal through
the battle scene's `OnTakeDamage(Damage, CauserCharaName, DamagedCharaName, ..., bHeal, ...)`, a `BlueprintImplementableEvent` that
`btsc_base` and several area scenes override. A Lua hook on it never fires in this game's UE4SS 3.0.1 (see the tests below), so a
small C++ mod, **Battle Meters Native** (`native/`), reads it instead:

- at load, never during play, it registers a `ProcessEvent` pre-callback, and looks up `OnTakeDamage`'s name index.
- per call, it compares the called function's name index with that one: one integer compare. A match has `Damage`,
  `CauserCharaName`, `DamagedCharaName` and `bHeal` read at the offsets the game's own reflection gives, after checking each one's
  name and type. A function whose parameters don't fit is skipped.
- it queues the hit (2,048 at most, oldest dropped first), and registers `BattleMetersNativeHit()` and `BattleMetersNativeStatus()`
  into Battle Meters' Lua state before its `main.lua` runs. `native_hits.lua` takes the queue on each tick.

It's built against the UE4SS 3.0.1 (`c0a8d4c`) headers and import library. On another UE4SS build, Windows won't load it if an
import is missing, or it finds no name lookup and hooks nothing. Either way Battle Meters falls back to totals. A build whose
exports match but whose internals differ could still crash, which is why it's a separate, optional mod.

`attribution.lua` matches each hit to an HP change Battle Meters already measured, first in the same tick, then within 1 second.
Damage is matched to HP an enemy lost; a heal to HP a party member gained. That means:

- the totals are unchanged: still the HP lost and gained.
- no one is credited more than really changed, so overkill and overhealing don't count.
- hits by anyone outside the party (summons, enemies) use up the change they explain, but aren't credited.
- change no hit explains, such as poison or Regen, shows as grey **Unattributed**.

Party members are matched by the names `EndBattleAPI:GetActorName` and `GetCharaID` give for each one. Enemies are matched by
`GetActorName`. Hits on the party are damage taken, which is already split by who took it. If no hit matches during a battle, DPS
shows the total only and HPS keeps its line by who received the healing, as in 1.0.0.

Each battle's log lines, `damage by character: split [...]` and `healing by character: split [...]`, give the split, hits matched,
hits on unknown targets and unknown causers.

### What the tests found

**First live test, 2026-11-08:** one field fight, Cloud, Aerith and Tifa against Mandragoras and Kalm Fangs, 191 s. The hook went on
`/Game/BluePrint/BattleScene/Common/btsc_base.btsc_base_C:OnTakeDamage` and received nothing: 0 hits matched and 0 on unknown targets,
against 5,124 damage. Any event with damage is counted in one of those, whatever its names, so the hook saw no hits. The hook caused
no problems, and the panel fell back to the total as designed. The party's actor names are `Cloud`, `Aerith` and `Tifa`, with chara
IDs `PC0000_00`, `PC0003_00` and `PC0002_00`.

**Probe run, 2026-11-08** (`tools/probe`): one field fight, 2 Mu and a Levrikon. The fight has exactly one scene actor,
`btsc_base_C`, so the first test hooked the right class. The probe hooked 15 Blueprint overrides: 4 scene events and 11 enemy AI
events, including `OnActionInvoke`, `OnProwlInvoke` and `OnAITimerInvoke`, which run all the time. None of them was called in about
3 minutes of combat. **Blueprint-event hooks registered during play don't fire in this game's UE4SS 3.0.1**, so the game may well
call `OnTakeDamage` and we can't see it. Damage by character needs another route, so the split stays off in practice and the panel
shows the total. Routes still open: a hook on a native (`/Script/`) function that runs per hit, or hooks registered before the
Blueprint classes load.

**Native probe, 2026-11-08** (`tools/native-probe`): a UE4SS C++ mod with a `ProcessEvent` pre-callback registered at load. One
field fight, 162 s, Cloud, Aerith and Tifa against 2 Mu and a Levrikon. **The scene's `OnTakeDamage` reached the callback on every
hit**: 505 calls, each with `Damage`, `CauserCharaName`, `DamagedCharaName`, `AbilityId` and `bHeal`. The names are the same ones
`GetActorName` gives (`Tifa`, `mobgrasa_Mu_Rare_000@Grassland_mob_23`).

| | Probe (raw `Damage`) | Battle Meters (HP change) |
| --- | --- | --- |
| Damage taken by the party | 1,139 | 1,139 |
| Damage dealt by the party | 5,245 (Tifa 3,839, Cloud 790, Aerith 616) | 3,636 |
| Healing | 6,762 | 1,343 |

`Damage` is the hit's value before the target's HP runs out: the gap in damage dealt is overkill on killing blows (Tifa's Limit Break
hit the last Mu for 1,592, and the meter's biggest HP loss was 521). Healing includes overheal. Capping each hit by the HP actually lost,
as `attribution.lua` already does, handles both. The callback cost a mean 0.39 µs per `ProcessEvent` (1.14 million in about 8 minutes,
443 ms in total, 604 µs at most, including the log writes). No harness or game problems.

So the split needs native code: Lua can't receive these events in this UE4SS build. We chose an optional C++ mod tied to UE4SS 3.0.1
(Battle Meters Native, above). Lua-only routes are a separate issue.

Set `damage_by_character = false` in `config.lua` to turn the split off.

## What was tested

In the real game, on 2026-11-03, on a Level 17 save.

| Test | Result |
| --- | --- |
| Field fight, 2 Elphadunks of 1,179 HP | Damage total 2,358, exact, in several fights |
| Combat Assignment, 2 Venorats of 1,616 HP | Damage total 3,232, exact, in several fights |
| Stepping through all the meters mid-fight, past Off | Total still exact |
| The key, sent to the game and pressed by hand | Steps through the meters |
| Starting off, and remembering the choice | Works, and survives reinstalling |
| Riding a chocobo, then a fight | Measured. A two-minute ride no longer turns the mod off (the fix itself is only tested by the shorter rides) |
| Tutorial course in the simulator | Panel shows, numbers count |
| Training Dummy course | Only that mod's panel shows |
| Install and uninstall | Clean; Training Dummy untouched; game loads |
| MP spent | Counted, 38 in one fight |

## Limits

- **Reads every 200 ms.** Hits within the same read count as one for "Biggest hit". Totals aren't affected.
- **All HP changes count**, whatever caused them. Revives, potions, Regen ticks, HP Absorb, abilities that heal without MP and any refill from the game count as healing.
  Only HP actually gained is counted, so overhealing adds nothing. These follow from how the mod reads HP: Regen, HP Absorb and MP-free heals weren't tested one by one.
- **MP spent is all the party's MP,** on any spell. MP gained isn't subtracted. Healing per MP is all healing divided by all of that MP, so offensive spells lower it and
  MP-free healing raises it. It only shows true healing efficiency if healing is all the party spends MP on.
- **Changes within one read net out.** A character who takes 100 and gets 300 healing in the same 200 ms records 200 healing and no damage taken, so HPS and DTPS can both
  read slightly low in busy moments. MP nets out the same way.
- **Game time:** it stops when paused and runs slower when the game slows down. A 142 s fight showed as 85 s.
- **A fight's first second:** outside a fight the mod checks once a second, so up to a second of the start can be missed.
- **The last enemy:** one killed in one blow from above half HP doesn't have that blow counted. Running away is untested: enemies still
  listed are treated as alive, but if the list is empty, one at half HP or less would count.
- **Not tested:** boss fights, scenes during a fight, summons, guest characters, other mods. The colours of characters outside our party
  are set but haven't been seen in-game.
- **The panel can cover other UI:** it hides when paused, and it hasn't been checked against every screen.
