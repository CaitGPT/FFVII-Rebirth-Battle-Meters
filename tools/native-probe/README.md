# Native hit probe (development only)

`BattleMetersNativeHits` is a UE4SS C++ mod for [issue 1](https://github.com/CaitGPT/FFVII-Rebirth-Battle-Meters/issues/1). It isn't
part of the release, and it changes nothing in the game.

The Lua probe (`../probe`) showed that Lua `RegisterHook` on Blueprint overrides never fires in this game's UE4SS 3.0.1: 15 hooks and
0 calls in a 3-minute fight. The engine still sends those events through `UObject::ProcessEvent`, which UE4SS hooks itself. This probe
registers a `ProcessEvent` pre-callback at load, as the project's telemetry exporter does, never during play. It logs each call to:

- the scene's `OnTakeDamage`, `OnIncrementBattleCountPerID` and `OnCharaPartsDamage`.
- the AI's `OnTakeDamageInvoke`, `OnTakeDamageHPFirstInvoke`, `OnGiveDamageInvoke` and `OnTakeDamageOverTime`.
- `OnActionInvoke` as a control, which runs all the time: counted, and only its first 5 calls logged.

Each call is matched by its name's index, one integer compare per `ProcessEvent`. A matched call is logged with its parameters,
decoded by their reflected types and offsets: ints, floats, names, bools, bytes and object names. The output is `hits.log` next to
the mod folder, with a count line every 10 seconds.

## Build and run

1. With the game closed, run `Build.ps1`. It uses the same pinned UE4SS v3.0.1 sources, Visual Studio Build Tools and import
   library as the telemetry exporter, and prints the DLL's hash.
2. Copy `main.dll` to `ue4ss\Mods\BattleMetersNativeHits\dlls\main.dll` and add `BattleMetersNativeHits : 1` to `mods.txt`.
3. Fight one field battle. Battle Meters 1.0.0 set to DPS gives the exact HP total to compare against.
4. Read `ue4ss\Mods\BattleMetersNativeHits\hits.log`, then remove the folder and the line.

`UObjectBase::GetNamePrivate` is looked up in `UE4SS.dll` by its exported name. The pinned headers declare `FName` as a struct and
the DLL exports it as a class, so the linker can't match it. The first log line says whether the lookup worked.

## Reading the result

- **`OnTakeDamage` lines with damage, causer and target that add up to the HP lost:** per-character damage works natively. Battle
  Meters would then read `hits.log`, or a lighter version of this DLL, instead of the Lua hook.
- **Only the control counts up:** the game doesn't send those events in a field fight, and we need another source.
- **Nothing counts, control included:** `ProcessEvent` doesn't see Blueprint events dispatched by native code here either.

Shipping a native DLL would tie the release to UE4SS 3.0.1. That's a decision for the owner before release, not for the probe.
