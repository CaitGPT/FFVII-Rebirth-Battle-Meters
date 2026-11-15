"""Draw every compact layout as a web page, from the same Lua the game runs, to check a change without starting the game.

    python -m pip install lupa
    python tools/preview/render.py [meters.json] [--scale 1.0] [--out preview.html]

With a meters.json (written next to the mod during play), it draws that fight; otherwise a sample one. Text is Roboto at
the game's point sizes, so widths are close to, not exactly, the game's. The panel sprite is approximated with a gradient.
"""
import argparse
import html
import json
import pathlib

from lupa import lua54

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "ue4ss" / "BattleMeters" / "Scripts"
MODES = ["dps_compact", "dps_full", "hps_compact", "hps_full", "dtps_compact", "dtps_full", "grid", "stack"]

SAMPLE = {
    "elapsed": 197.9,
    "meters": {
        "damage": {"average": 440, "recent": 976, "total": 87100, "biggest": 866,
                   "by_source": {"Barret": 51778, "Red XIII": 17074, "Yuffie": 18248}},
        "heal": {"average": 68.7, "recent": 0, "total": 13593, "biggest": 1178,
                 "by_source": {"Barret": 8741, "Red XIII": 2690, "Yuffie": 2162}},
        "taken": {"average": 69.7, "recent": 0, "total": 13794, "biggest": 1255,
                  "by_source": {"Barret": 8627, "Red XIII": 2967, "Yuffie": 2200}},
        "mp": {"average": 0, "recent": 0, "total": 0, "biggest": 0, "by_source": {}},
    },
}


def to_lua(lua, value):
    if isinstance(value, dict):
        table = lua.table()
        for key, item in value.items():
            table[key] = to_lua(lua, item)
        return table
    return value


def css_color(c):
    return f"rgba({round(c['R'] * 255)},{round(c['G'] * 255)},{round(c['B'] * 255)},{c['A']:.2f})"


def render(view):
    parts = [f'<div class="panel" style="width:{view["width"]}px;height:{view["height"]}px">']
    for r in view["rects"].values():
        parts.append(f'<i style="left:{r["x"]}px;top:{r["y"]}px;width:{r["w"]}px;height:{r["h"]}px;'
                     f'background:{css_color(r["color"])}"></i>')
    align = {0: "left", 1: "center", 2: "right"}
    for t in view["texts"].values():
        # UMG font sizes are points at 96 DPI.
        parts.append(f'<span style="left:{t["x"]}px;top:{t["y"]}px;width:{t["w"]}px;height:{t["h"]}px;'
                     f'font-size:{t["size"] * 96 / 72:.1f}px;color:{css_color(t["color"])};'
                     f'text-align:{align[t["justify"]]}">{html.escape(t["text"])}</span>')
    parts.append("</div>")
    return "".join(parts)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("meters", nargs="?")
    parser.add_argument("--scale", type=float, default=1.0)
    parser.add_argument("--out", default=str(pathlib.Path(__file__).with_name("preview.html")))
    args = parser.parse_args()
    data = json.loads(pathlib.Path(args.meters).read_text()) if args.meters else SAMPLE

    lua = lua54.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'package.path = "{SCRIPTS.as_posix()}/?.lua;" .. package.path')
    view_module = lua.eval('(require("compact_view"))')
    kinds = {}
    for kind, k in data["meters"].items():
        k = dict(k)
        # meters.json doesn't say whether damage and healing were split by who did it; a split means they were.
        if kind in ("damage", "heal") and k.get("by_source"):
            k["attributed"] = True
        kinds[kind] = k
    snapshot = to_lua(lua, {"elapsed": data["elapsed"], "kinds": kinds})
    config = to_lua(lua, {"rolling_window_seconds": 5, "scale": args.scale})

    cells = []
    for mode in MODES:
        view = view_module.build(snapshot, mode, config)
        cells.append(f'<figure><figcaption>{mode}</figcaption>{render(view)}</figure>')
    page = f"""<!doctype html><meta charset="utf-8"><title>Battle Meters preview</title>
<style>
body{{margin:0;padding:16px;background:#1c1f22;color:#ccc;font-family:Segoe UI,sans-serif}}
.wrap{{display:flex;flex-wrap:wrap;gap:20px;align-items:flex-start}}
figure{{margin:0;padding:14px;background:radial-gradient(120% 90% at 70% 30%,#5b6b53,#2c3a31 45%,#151c1b);border-radius:6px}}
figcaption{{font-size:12px;margin-bottom:8px;color:#ddd}}
.panel{{position:relative;font-family:Roboto,Arial,sans-serif;
  background:linear-gradient(90deg,rgba(14,26,40,.92),rgba(18,34,52,.86) 70%,rgba(18,34,52,.55))}}
.panel i,.panel span{{position:absolute;display:block}}
.panel span{{white-space:nowrap;overflow:visible;text-shadow:1.5px 1.5px 0 rgba(0,0,0,.95);line-height:1.15}}
</style><div class="wrap">{''.join(cells)}</div>"""
    pathlib.Path(args.out).write_text(page, encoding="utf-8")
    print(args.out)


if __name__ == "__main__":
    main()
