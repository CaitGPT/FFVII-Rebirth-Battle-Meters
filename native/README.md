# Battle Meters Native

An optional UE4SS C++ mod that gives Battle Meters the game's hit events, for damage and healing by character. It changes nothing
in the game. Built for **UE4SS 3.0.1** (`c0a8d4c`) only. How it works and what the tests found:
[docs/HOW-IT-WORKS.md](../docs/HOW-IT-WORKS.md#damage-and-healing-by-character-battle-meters-native).

## Build

Run `Build.ps1`. It builds against pinned UE4SS v3.0.1 sources and an import library for the `UE4SS.dll` you run, and prints the
DLL's hash. The output is `build/native/Release/main.dll`. Each build's hash differs, because the compiler stamps it; the release
lists the hash of the DLL that was tested.

The machine's paths (CMake, a UE4SS v3.0.1 checkout with its `UEPseudo` and header dependencies, the import library, and the
interface script) go in `tools/build-config.local.json`, which isn't in git. The comments at the top of `Build.ps1` list each one.

## Install

Put `main.dll` in `ue4ss/Mods/BattleMetersNative/dlls/main.dll`, and add `BattleMetersNative : 1` to `mods.txt` above
`BattleMeters : 1`. `tools/Install-BattleMeters.ps1 -Mode Install -WithNative` does both.

## What Battle Meters sees

The mod registers two functions into Battle Meters' Lua state:

- `BattleMetersNativeHit()` returns `damage, causer, target, heal` for the oldest queued hit, or nothing.
- `BattleMetersNativeStatus()` returns `"ok"` once it's hooked (otherwise why not), the hits dropped since the last call, and the
  hits queued since load.

Battle Meters logs the status at the first battle: `hit events: Battle Meters Native is hooked`, or why it isn't.

`UObjectBase::GetNamePrivate` is looked up in `UE4SS.dll` by its exported name. The 3.0.1 headers declare `FName` as a struct and
the DLL exports it as a class, so the linker can't match it. If the lookup fails, nothing is hooked.
