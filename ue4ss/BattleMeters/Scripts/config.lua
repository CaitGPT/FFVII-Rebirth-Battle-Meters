-- Battle Meters settings. Edit, then restart the game (UE4SS hot reload crashes this game).
-- The meter you last chose is remembered in settings.txt, next to the Scripts folder.
return {
    -- How often the mod reads HP during a battle, in milliseconds. Outside battles it checks once a second.
    tick_ms = 200,

    -- Rolling window for the "Last 5 seconds" line.
    rolling_window_seconds = 5,

    -- Seconds the final numbers stay on screen after a battle.
    linger_seconds = 8,

    -- Seconds a battle must stay over before it counts as finished, so a moment between waves doesn't reset it.
    battle_end_grace_seconds = 2,

    -- Position in 1920x1080 units from the top left corner of the screen. This sits below the objective list a Combat
    -- Assignment puts in the top left, and above the combat help.
    overlay_x = 48,
    overlay_y = 240,

    -- Pressed with Ctrl+Shift, this steps through DPS, HPS, DTPS and off.
    cycle_key = "D",

    -- Split damage dealt and healing done by character, from the game's own hit events. Needs the optional Battle
    -- Meters Native mod (UE4SS 3.0.1). Hits are only credited up to the HP really lost or gained, and whatever no hit
    -- explains shows as Unattributed. Without it, or in a scene that sends no hit events, the panel shows totals.
    damage_by_character = true,

    -- Write meters.json next to this mod, for stream overlays and tests.
    write_json = true,

    -- Log what the mod sees to UE4SS.log.
    debug = false,
}
