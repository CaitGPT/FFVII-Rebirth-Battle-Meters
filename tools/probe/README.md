# Hit probe (development only)

`BattleMetersHitProbe` is a UE4SS mod for one live test of [issue 1](https://github.com/CaitGPT/FFVII-Rebirth-Battle-Meters/issues/1).
It isn't part of the release. It changes nothing in the game. It only hooks callbacks and logs them to `UE4SS.log`.

The first live test hooked `btsc_base_C:OnTakeDamage` and got no calls (see `docs/HOW-IT-WORKS.md`). The probe answers why, in one
field fight:

1. Which battle-scene actors exist in a fight, and their class chains. Was the `btsc_base` we hooked the fight's scene?
2. Whether Blueprint-event hooks fire at all in this UE4SS build. The controls are enemy AI events such as `OnActionInvoke`, which run
   all the time.
3. Which per-hit callbacks run, and with which names: the scene's `OnTakeDamage`, `OnIncrementBattleCountPerID` (attacker and target
   per hit, no amount) and `OnCharaPartsDamage`, and the enemy AI's `OnTakeDamageInvoke` and `OnTakeAbilityInvoke`.

## Running it

1. Copy `BattleMetersHitProbe` into `ue4ss\Mods` and add `BattleMetersHitProbe : 1` to `mods.txt`. Battle Meters 1.0.0 can stay
   installed: its HP totals give the damage to compare against.
2. Fight one ordinary field battle.
3. In `UE4SS.log`, read the `[BattleMetersHitProbe]` lines: `scene actor`, `class chain`, `hooked`, the first calls of each callback
   with their parameters, and the call count for each callback at the end.
4. Remove the folder and the `mods.txt` line.

## Reading the result

- **Controls count up and `OnTakeDamage` stays at 0:** the game doesn't call it in that fight. Use whichever per-hit callback does run.
  If only `OnIncrementBattleCountPerID` runs, it says who hit whom but not for how much. Then a hit can be credited only when one
  character alone hit that enemy within a read, and the rest stays Unattributed.
- **Nothing counts up, controls included:** Blueprint-event hooks don't work in this build, and the approach needs another route.
- **`OnTakeDamage` counts up:** the first test's scene wasn't the hooked class. The `scene actor` lines show which one to hook.
