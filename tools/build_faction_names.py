"""Writes Data/FactionNames_<flavor>.lua, the names in every client locale and the side, of each faction a QuestAvailable
file's rep table names, from the client's Faction table through wago.tools."""
import csv
import io
import os
import re
import sys
import time
import urllib.request
from pathlib import Path

LOCALES = ["enUS", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW"]
SLOTS = range(4)
COLUMNS = ("ID", "Name_lang") + tuple(f"ReputationBase_{i}" for i in SLOTS) + tuple(
    f"ReputationRaceMasks{i}_{w}" for i in SLOTS for w in (0, 1))
HATED = -42000
HEADERS = {469: "Alliance", 67: "Horde"}


def checked(text, where):
    header = next(csv.reader(io.StringIO(text)), [])
    missing = [c for c in COLUMNS if c not in header]
    if missing:
        sys.exit(f"{where}: no {', '.join(missing)} column, refusing it")
    return text


def fetch(build, locale, cache):
    path = cache / f"Faction_{build}_{locale}.csv"
    if path.exists():
        return checked(path.read_bytes().decode("utf-8"), path)
    url = f"https://wago.tools/db2/Faction/csv?build={build}&locale={locale}"
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        body = r.read()
    text = checked(body.decode("utf-8"), url)
    tmp = path.with_suffix(".part")
    tmp.write_bytes(body)
    os.replace(tmp, path)
    time.sleep(0.3)
    return text


def names(text, wanted):
    found = {}
    for row in csv.DictReader(io.StringIO(text)):
        try:
            fid = int(row["ID"])
        except (KeyError, ValueError):
            continue
        name = row.get("Name_lang", "")
        if fid in wanted and name:
            if any(ord(ch) < 32 for ch in name):
                sys.exit(f"faction {fid} has a control character in its name, refusing it")
            found[fid] = name
    return found


def slots(row):
    def mask(i):
        low, high = (int(row[f"ReputationRaceMasks{i}_{w}"]) & 0xFFFFFFFF for w in (0, 1))
        return low | high << 32
    return [(int(row[f"ReputationBase_{i}"]), mask(i)) for i in SLOTS]


# A faction one side cannot earn starts a race set holding that side's whole one at Hated, so it belongs to the other side
def sides(text, wanted):
    rows = {}
    for row in csv.DictReader(io.StringIO(text)):
        try:
            rows[int(row["ID"])] = row
        except (KeyError, ValueError):
            continue
    races = {}
    for fid, side in HEADERS.items():
        if fid not in rows:
            sys.exit(f"faction {fid} ({side}) is missing, refusing to write")
        races[side] = slots(rows[fid])[0][1]
    if races["Alliance"] & races["Horde"] or 0 in races.values():
        sys.exit("the Alliance and Horde race sets do not read apart, refusing to write")
    out = {}
    for fid in wanted:
        closed = {side for base, mask in slots(rows[fid]) if base <= HATED for side, r in races.items() if mask & r == r}
        if len(closed) == 1:
            out[fid] = "Horde" if closed == {"Alliance"} else "Alliance"
    for fid, side in HEADERS.items():
        if fid in wanted and out.get(fid) != side:
            sys.exit(f"faction {fid} does not read as {side}, refusing to write")
    return out


def rep_factions(data_file):
    text = Path(data_file).read_text(encoding="utf-8")
    block = re.search(r"^rep = \{\n(.*?)^\},", text, re.S | re.M)
    if not block:
        sys.exit(f"{data_file}: no rep table")
    wanted = set()
    for row in re.findall(r"^\t\[\d+\]=\{([-\d,]+)\},$", block.group(1), re.M):
        values = [int(v) for v in row.split(",")]
        wanted.update(values[0::2])
    if not wanted:
        sys.exit(f"{data_file}: an empty rep table")
    return wanted


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    if len(sys.argv) < 5:
        sys.exit("usage: build_faction_names.py <build> <output .lua> <cache dir> <QuestAvailable data file> [...]")
    build, out, cache, data_files = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4:]
    cache.mkdir(parents=True, exist_ok=True)
    wanted = set()
    for data_file in data_files:
        wanted |= rep_factions(data_file)
    # Each of the Aldor and the Scryers loses reputation when the other gains, so the Quest Browser names the one the data leaves out
    if wanted & {932, 934}:
        wanted |= {932, 934}
    texts = {loc: fetch(build, loc, cache) for loc in LOCALES}
    per = {loc: names(texts[loc], wanted) for loc in LOCALES}
    english = per["enUS"]
    lacking = sorted(wanted - set(english))
    if lacking:
        sys.exit(f"faction(s) {lacking} have no enUS name in build {build}, refusing to write")
    for loc, table in per.items():
        if set(table) != set(english):
            sys.exit(f"{loc} names {len(table)} factions where enUS names {len(english)}, refusing to write")
    lines = [
        f"-- Generated by tools/build_faction_names.py from the client's Faction table, build {build}.\n",
        "-- The factions the quest data gives reputation with, by locale and faction id, for when the game names none.\n",
        "local _, ns = ...\n",
        "ns.FACTION_NAMES = {\n",
    ]
    for loc in LOCALES:
        body = ", ".join(f"[{fid}] = {lua_string(per[loc][fid])}" for fid in sorted(english))
        lines.append(f"    {loc} = {{ {body} }},\n")
    lines.append("}\n")
    side = sides(texts["enUS"], set(english))
    body = ", ".join(f"[{fid}] = {lua_string(side[fid])}" for fid in sorted(side))
    lines.append("-- The side a faction belongs to, where the other side cannot earn it\n")
    lines.append(f"ns.FACTION_SIDE = {{ {body} }}\n")
    tmp = out.with_suffix(".part")
    tmp.write_bytes("".join(lines).encode("utf-8"))
    os.replace(tmp, out)
    print(f"{out}: {len(english)} factions in {len(LOCALES)} locales, {len(side)} on one side, from build {build}")


main()
