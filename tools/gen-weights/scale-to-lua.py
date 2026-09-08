#!/usr/bin/env python3
"""Turn SimulationCraft scale-factor reports into Core/WeightsData.lua.

Usage: scale-to-lua.py <simc-checkout> <out-dir> <WeightsData.lua> <iterations> <season>

One entry per specialization id. When several profiles share a spec (hero
talent variants), the one with the shortest file name is the default profile
and wins; the others are listed under variants for reference.
"""
import datetime
import glob
import json
import os
import re
import subprocess
import sys

SIMC_DIR, OUT, TARGET, ITER, SEASON = sys.argv[1:6]

# SimC class/spec names -> WoW specialization id (matches Core/Data.lua).
SPEC_IDS = {
    ("warrior", "arms"): 71, ("warrior", "fury"): 72, ("warrior", "protection"): 73,
    ("paladin", "holy"): 65, ("paladin", "protection"): 66, ("paladin", "retribution"): 70,
    ("hunter", "beast_mastery"): 253, ("hunter", "marksmanship"): 254, ("hunter", "survival"): 255,
    ("rogue", "assassination"): 259, ("rogue", "outlaw"): 260, ("rogue", "subtlety"): 261,
    ("priest", "discipline"): 256, ("priest", "holy"): 257, ("priest", "shadow"): 258,
    ("deathknight", "blood"): 250, ("deathknight", "frost"): 251, ("deathknight", "unholy"): 252,
    ("shaman", "elemental"): 262, ("shaman", "enhancement"): 263, ("shaman", "restoration"): 264,
    ("mage", "arcane"): 62, ("mage", "fire"): 63, ("mage", "frost"): 64,
    ("warlock", "affliction"): 265, ("warlock", "demonology"): 266, ("warlock", "destruction"): 267,
    ("monk", "brewmaster"): 268, ("monk", "mistweaver"): 270, ("monk", "windwalker"): 269,
    ("druid", "balance"): 102, ("druid", "feral"): 103, ("druid", "guardian"): 104, ("druid", "restoration"): 105,
    ("demonhunter", "havoc"): 577, ("demonhunter", "vengeance"): 581, ("demonhunter", "devourer"): 1480,
    ("evoker", "devastation"): 1467, ("evoker", "preservation"): 1468, ("evoker", "augmentation"): 1473,
}

# SimC scale factor keys -> Sift canonical stat keys.
KEYS = {
    "Str": "STRENGTH", "Agi": "AGILITY", "Int": "INTELLECT", "Stam": "STAMINA",
    "Crit": "CRIT", "Haste": "HASTE", "Mastery": "MASTERY", "Vers": "VERSATILITY",
    "Wdps": "DPS", "WOHdps": "DPS_OH", "Armor": "ARMOR", "Leech": "LEECH",
    "Avoidance": "AVOIDANCE", "Speed": "SPEED",
}
PRIMARIES = ("STRENGTH", "AGILITY", "INTELLECT")


def git(*args):
    try:
        return subprocess.check_output(["git", "-C", SIMC_DIR, *args], text=True).strip()
    except Exception:
        return ""


def profile_meta(path):
    cls, spec = None, None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            m = re.match(r'^(\w+)="', line)
            if m and cls is None:
                cls = m.group(1)
            m = re.match(r"^spec=(\w+)", line)
            if m:
                spec = m.group(1)
            if cls and spec:
                break
    return cls, spec


def errors_from_text(path, name):
    """Per-stat standard error from the text report's Scale Factors line."""
    out = {}
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return out
    m = re.search(r"^Scale Factors:\n\s+%s\s+(.*)$" % re.escape(name), text, re.M)
    if not m:
        return out
    for key, val, err in re.findall(r"(\w+)=([-\d.]+)\(([-\d.]+)\)", m.group(1)):
        if key in KEYS:
            out[KEYS[key]] = float(err)
    return out


entries = {}
for jpath in sorted(glob.glob(os.path.join(OUT, "*.json"))):
    name = os.path.splitext(os.path.basename(jpath))[0]
    cls, spec = profile_meta(os.path.join(SIMC_DIR, "profiles", SEASON, name + ".simc"))
    spec_id = SPEC_IDS.get((cls, spec))
    if not spec_id:
        print("skip %s: unknown class/spec %s/%s" % (name, cls, spec), file=sys.stderr)
        continue
    with open(jpath, encoding="utf-8") as fh:
        data = json.load(fh)
    player = data["sim"]["players"][0]
    raw = {KEYS[k]: v for k, v in (player.get("scale_factors") or {}).items() if k in KEYS}
    primary = max((raw.get(p, 0.0) for p in PRIMARIES), default=0.0)
    if primary <= 0:
        print("skip %s: no primary stat scale factor" % name, file=sys.stderr)
        continue
    weights = {k: v / primary for k, v in raw.items() if v > 0}
    dps = player.get("collected_data", {}).get("dps", {}).get("mean")
    entry = {
        "id": spec_id, "profile": name, "class": cls, "spec": spec,
        "weights": weights, "raw": raw, "error": errors_from_text(os.path.join(OUT, name + ".txt"), name),
        "dps": dps, "talents": player.get("talents"),
    }
    cur = entries.get(spec_id)
    if cur is None or len(name) < len(cur["profile"]):
        if cur is not None:
            entry["variants"] = cur.get("variants", []) + [cur["profile"]]
        entries[spec_id] = entry
    else:
        cur.setdefault("variants", []).append(name)

version = data.get("version", "?") if entries else "?"
commit = git("rev-parse", "HEAD") or data.get("git_revision", "?")
branch = git("rev-parse", "--abbrev-ref", "HEAD") or data.get("git_branch", "?")
today = datetime.date.today().isoformat()


def lua_num(v):
    return "%.4f" % v


def lua_stats(d):
    keys = sorted(d)
    return "{ " + ", ".join("%s = %s" % (k, lua_num(d[k])) for k in keys) + " }"


lines = []
lines.append("-- GENERATED by tools/gen-weights on %s. Do not edit by hand." % today)
lines.append("-- SimulationCraft %s (%s, branch %s), profiles/%s, %s iterations per sim," % (version, commit[:9], branch, SEASON, ITER))
lines.append("-- scale factors over dps for every role. Weights are per stat point relative")
lines.append("-- to the spec's primary stat. raw is dps per point, error its standard error.")
lines.append("-- DPS_OH is the value of a point of off-hand weapon dps for dual wielders.")
lines.append("local _, ns = ...")
lines.append("")
lines.append("ns.WeightsData = {")
lines.append('  generated = "%s", simc = "%s", commit = "%s", branch = "%s", season = "%s", iterations = %s,' % (today, version, commit, branch, SEASON, ITER))
lines.append("  specs = {")
for spec_id in sorted(entries):
    e = entries[spec_id]
    lines.append("    [%d] = {" % spec_id)
    lines.append('      profile = "%s", dps = %s,' % (e["profile"], ("%.0f" % e["dps"]) if e["dps"] else "nil"))
    if e.get("variants"):
        lines.append("      variants = { %s }," % ", ".join('"%s"' % v for v in sorted(e["variants"])))
    lines.append("      weights = %s," % lua_stats(e["weights"]))
    lines.append("      raw = %s," % lua_stats(e["raw"]))
    if e["error"]:
        lines.append("      error = %s," % lua_stats(e["error"]))
    lines.append("    },")
lines.append("  },")
lines.append("}")
lines.append("")

with open(TARGET, "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines))
print("wrote %s with %d specs" % (TARGET, len(entries)))
for spec_id in sorted(entries):
    e = entries[spec_id]
    w = e["weights"]
    order = sorted((k for k in w if k in ("CRIT", "HASTE", "MASTERY", "VERSATILITY")), key=lambda k: -w[k])
    print("  %5d %-40s %s" % (spec_id, e["profile"], "  ".join("%s %.2f" % (k[:4], w[k]) for k in order)))
