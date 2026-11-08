# Changelog

## 1.1.0 (2026-11-08)

- Damage and healing by character, with the optional Battle Meters Native mod (UE4SS 3.0.1 only). DPS and HPS get a coloured
  line and one row per party member: who dealt the damage, and who did the healing. Each is credited only up to the HP really
  lost or gained, so overkill and overhealing don't count, and whatever no hit explains (poison, Regen) shows as Unattributed.
  The totals are unchanged.
- DTPS shows one row per party member for the damage each one took, under its line. It needs no hit events, so it works
  without Battle Meters Native too.
- Without Battle Meters Native, or in a scene that sends no hit events, everything works as in 1.0.0: DPS shows the total, and
  HPS's line is by who received the healing.
- `meters.json` includes each meter's split.

## 1.0.0 (2026-11-03)

First release.

- A small panel with DPS, HPS or DTPS in any battle. Ctrl+Shift+D steps through them and off, and the mod starts off.
- HPS shows MP spent and healing per MP.
- A coloured line on HPS and DTPS shows each party member's share: who received the healing, and who took the damage.
- Resets at each battle. The last numbers stay for 8 seconds.
- Works alongside Training Dummy: on its courses, only its panel shows.
