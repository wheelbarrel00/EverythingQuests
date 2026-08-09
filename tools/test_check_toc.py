#!/usr/bin/env python3
"""Prove check_toc.py fires on each drift shape, and prove it stays quiet on a good tree.

A gate needs a test that it does NOT fire as well as one that it does. The sibling addon's
suite asserts that a flavor TOC omitting a shared file exits 0, because there that omission
is legal by design. "a shared file missing from a flavor TOC fails" below is the same tree
with the opposite expectation, and that inversion is the reason this file exists.

The stays-quiet half is load bearing too. A flavor TOC is legitimately a different file
list: it may carry a data source no retail TOC has, and it may skip a module that flavor
cannot run when the omission is declared. Both are named cases here so a future tightening
of the rule cannot quietly outlaw them.

Several cases assert on OUTPUT as well as exit code, deliberately left uncounted here so
the number cannot rot. A scaffold TOC and a gitignored TOC both pass, and passing silently
is the failure mode that matters for them - a green run must still say out loud what it did
not check. The failing cases that assert output do it to pin the message on the one thing
someone reading it has to act on.

Builds throwaway trees under a temp directory, so it never touches the real checkout. No
pytest dependency, matching every other gate in this repo.
"""
import copy
import io
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_toc  # noqa: E402

RETAIL = "EverythingQuests.toc"
MAINLINE = "EverythingQuests_Mainline.toc"
VANILLA = "EverythingQuests_Vanilla.toc"
TBC = "EverythingQuests_TBC.toc"

HEADER = (
    "## Interface: {interface}\n"
    "## Title: Everything Quests\n"
    "## Version: {version}\n"
    "## X-Curse-Project-ID: {project}\n"
)

RETAIL_FILES = [
    "Core/Init.lua",
    "Core/FlavorProbe.lua",
    "Modules/QuestAuto.lua",
    "Modules/MapPOI/Pin.xml",
]
SCAFFOLD_FILES = ["Core/Init.lua", "Core/FlavorProbe.lua"]

CLASSIC_DATA = "Data/QuestChains/_Coords_Classic.lua"
LUAS = RETAIL_FILES + [CLASSIC_DATA]

RETAIL_HEAD = {"interface": "120100, 120007", "version": "1.38.1", "project": "1544648"}
CLASSIC_HEAD = {"version": "1.38.1", "project": "1544648"}

GOOD = {
    RETAIL: dict(RETAIL_HEAD, files=list(RETAIL_FILES)),
    VANILLA: dict(CLASSIC_HEAD, interface="11509", files=list(SCAFFOLD_FILES),
                  scaffold=True),
    TBC: dict(CLASSIC_HEAD, interface="20506", files=list(SCAFFOLD_FILES), scaffold=True),
}

# The good tree keeps a Classic-only data file on disk that no TOC above lists, so most
# cases would trip "no TOC lists it" for an unrelated reason. Only the cases that care
# about it pass the full LUAS list.
BASE_LUAS = list(RETAIL_FILES)


def run(tocs, luas, gitignore=None):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for d in check_toc.SOURCE_DIRS:
            (root / d).mkdir(parents=True, exist_ok=True)
        for rel in luas:
            p = root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("-- test\n", encoding="utf-8")
        for name, spec in tocs.items():
            body = HEADER.format(
                interface=spec["interface"],
                version=spec["version"],
                project=spec["project"],
            )
            if spec.get("scaffold"):
                body += "\n# check-toc: scaffold\n"
            for rel in spec.get("omits", []):
                body += f"# check-toc: omit {rel}\n"
            for rel in spec.get("flavor_only", []):
                body += f"# check-toc: flavor-only {rel}\n"
            body += "\n"
            body += "".join(f.replace("/", "\\") + "\n" for f in spec["files"])
            (root / name).write_text(body, encoding="utf-8")
        if gitignore is not None:
            (root / ".gitignore").write_text("\n".join(gitignore) + "\n", encoding="utf-8")
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = check_toc.main(root)
        return code, buf.getvalue()


CASES = []


def case(name, expected, tocs, luas, gitignore=None, expect_out=None):
    CASES.append((name, expected, tocs, luas, gitignore, expect_out))


def _with(**edits):
    tocs = copy.deepcopy(GOOD)
    for toc_name, changes in edits.items():
        tocs[toc_name].update(changes)
    return tocs


def _full(**changes):
    """A flavor TOC promoted out of scaffold mode - the shape EQ grows into.

    scaffold=False is explicit because _with() merges rather than replaces, so leaving it
    off would inherit the fixture's scaffold flag and every coverage case would pass by
    being skipped. That is not hypothetical - it is what these cases did before the flag
    was written out, and the headline case is the only one that noticed.
    """
    spec = dict(CLASSIC_HEAD, interface="11509", files=list(RETAIL_FILES), scaffold=False)
    spec.update(changes)
    return spec


# --- must stay quiet -------------------------------------------------------------------

case("a clean tree passes", 0, copy.deepcopy(GOOD), BASE_LUAS)

case(
    "a full flavor TOC listing everything the retail TOC lists passes",
    0,
    _with(**{VANILLA: _full()}),
    BASE_LUAS,
)

case(
    "a flavor TOC may omit a file when the omission is declared",
    0,
    _with(**{VANILLA: _full(
        files=[f for f in RETAIL_FILES if f != "Modules/MapPOI/Pin.xml"],
        omits=["Modules/MapPOI/Pin.xml"],
    )}),
    BASE_LUAS,
)

case(
    "a flavor TOC may list a file no retail TOC has",
    0,
    _with(**{VANILLA: _full(files=RETAIL_FILES + ["Data/QuestChains/_Coords_Classic.lua"])}),
    list(LUAS),
)

case(
    "an absent gitignored TOC passes and says it was not checked",
    0,
    {RETAIL: dict(RETAIL_HEAD, files=list(RETAIL_FILES))},
    BASE_LUAS,
    gitignore=["*.zip", VANILLA, TBC],
    expect_out=[f"{VANILLA}: NOT CHECKED", f"{TBC}: NOT CHECKED"],
)

case(
    "a scaffold TOC passes but still reports how much it does not list",
    0,
    copy.deepcopy(GOOD),
    BASE_LUAS,
    expect_out=[f"{VANILLA}: SCAFFOLD", "2 of 4 file(s)"],
)

case(
    "a present gitignored TOC passes and says CI will not see it",
    0,
    copy.deepcopy(GOOD),
    BASE_LUAS,
    gitignore=[VANILLA, TBC],
    expect_out=["CI never sees it"],
)

case(
    "a flavor-only file declared in the retail TOC and listed by a flavor TOC passes",
    0,
    _with(**{RETAIL: {"flavor_only": [CLASSIC_DATA]},
             VANILLA: {"files": SCAFFOLD_FILES + [CLASSIC_DATA]}}),
    list(LUAS),
    expect_out=[f"{CLASSIC_DATA}: FLAVOR-ONLY - listed by {VANILLA}"],
)

# THE case the directive exists for: the tree CI actually sees. The flavor TOC that lists
# the file is gitignored, so actions/checkout never materializes it and the file reads as
# listed by nothing. Compare with "a Classic-only data file with no directive fails" below -
# same tree, same checkout, and the directive is the only difference.
case(
    "a flavor-only file passes where no flavor TOC is on disk, and says it was not checked",
    0,
    {RETAIL: dict(RETAIL_HEAD, files=list(RETAIL_FILES), flavor_only=[CLASSIC_DATA])},
    list(LUAS),
    gitignore=[VANILLA, TBC],
    expect_out=[f"{CLASSIC_DATA}: FLAVOR-ONLY, NOT CHECKED"],
)

# --- must fire ---------------------------------------------------------------------------

# The regression the directive answers. Green locally, where the flavor TOC listing the file
# is on disk; red on the release tag, where it is not.
case(
    "a Classic-only data file with no directive fails in a simulated CI checkout",
    1,
    {RETAIL: dict(RETAIL_HEAD, files=list(RETAIL_FILES))},
    list(LUAS),
    gitignore=[VANILLA, TBC],
    expect_out=[f"no TOC lists {CLASSIC_DATA}"],
)

# Every flavor-only failure below is a way the directive could become a place coverage hides
# rather than a place it is declared.
case(
    "a flavor-only directive for a file that is not on disk fails",
    1,
    _with(**{RETAIL: {"flavor_only": ["Data/QuestChains/_Gone.lua"]}}),
    BASE_LUAS,
    expect_out=["stale", "no such file"],
)

case(
    "a flavor-only directive for a file the retail TOC lists fails",
    1,
    _with(**{RETAIL: {"files": RETAIL_FILES + [CLASSIC_DATA],
                      "flavor_only": [CLASSIC_DATA]}}),
    list(LUAS),
    expect_out=["stale", "not flavor only"],
)

# Declared where CI cannot read it, the directive changes nothing there and the file still
# fails coverage - while the tree looks reviewed.
case(
    "a flavor-only directive declared only in a gitignored TOC fails",
    1,
    _with(**{VANILLA: {"files": SCAFFOLD_FILES + [CLASSIC_DATA],
                       "flavor_only": [CLASSIC_DATA]}}),
    list(LUAS),
    gitignore=[VANILLA, TBC],
    expect_out=["CI never reads it"],
)

case(
    "a flavor-only file that no flavor TOC on disk lists fails",
    1,
    _with(**{RETAIL: {"flavor_only": [CLASSIC_DATA]}}),
    list(LUAS),
    expect_out=["no flavor TOC on disk lists it"],
)

# THE headline case. The sibling addon's gate anchors coverage on "listed by at least one
# TOC", so this exact tree passes there. Core/FlavorProbe.lua stays listed by the retail
# TOC and by TBC, which is what makes it invisible to that rule.
case(
    "a shared file missing from a flavor TOC fails",
    1,
    _with(**{VANILLA: _full(files=[f for f in RETAIL_FILES if f != "Modules/QuestAuto.lua"])}),
    BASE_LUAS,
    expect_out=["does not list Modules/QuestAuto.lua"],
)

case(
    "a TOC referencing a file that is not on disk fails",
    1,
    _with(**{VANILLA: dict(GOOD[VANILLA], files=SCAFFOLD_FILES + ["Core/NotThere.lua"])}),
    BASE_LUAS,
)

case(
    "an authored lua no TOC lists fails",
    1,
    copy.deepcopy(GOOD),
    BASE_LUAS + ["Modules/Orphan.lua"],
)

case(
    "an authored xml no TOC lists fails",
    1,
    copy.deepcopy(GOOD),
    BASE_LUAS + ["Modules/WorldQuests/Orphan.xml"],
)

case(
    "a mismatched ## Version: fails",
    1,
    _with(**{TBC: {"version": "1.38.0"}}),
    BASE_LUAS,
)

case(
    "a mismatched ## X-Curse-Project-ID: fails",
    1,
    _with(**{TBC: {"project": "9999999"}}),
    BASE_LUAS,
)

# Both directions of retail-pair drift. EQ has one retail TOC today, so these guard the
# moment a _Mainline sibling is added and the two stop being identical by definition.
case(
    "a _Mainline TOC listing a file the base TOC does not fails",
    1,
    dict(copy.deepcopy(GOOD),
         **{MAINLINE: dict(RETAIL_HEAD,
                           files=RETAIL_FILES + ["Data/QuestChains/_Coords_Classic.lua"])}),
    list(LUAS),
)

case(
    "the base TOC listing a file _Mainline does not fails",
    1,
    dict(copy.deepcopy(GOOD),
         **{MAINLINE: dict(RETAIL_HEAD, files=["Core/Init.lua"])}),
    BASE_LUAS,
)

# A declared omission that stops being true is worse than no directive at all: it reads as
# reviewed coverage while covering nothing.
case(
    "a stale omit directive for a file the TOC does list fails",
    1,
    _with(**{VANILLA: _full(omits=["Modules/QuestAuto.lua"])}),
    BASE_LUAS,
    expect_out=["stale"],
)

case(
    "a stale omit directive for a file the retail TOC does not list fails",
    1,
    _with(**{VANILLA: _full(omits=["Modules/Gone.lua"])}),
    BASE_LUAS,
    expect_out=["stale"],
)

# The message must name Mainline. It is the suffix a stray '_Retail.toc' most likely meant,
# and it lives in RETAIL_SUFFIXES rather than FLAVOR_SUFFIXES, so an error built from the
# flavor list alone lists every valid target except the right one.
case(
    "a TOC suffix the packager does not recognize fails",
    1,
    dict(copy.deepcopy(GOOD),
         **{"EverythingQuests_Retail.toc": dict(RETAIL_HEAD, files=list(RETAIL_FILES))}),
    BASE_LUAS,
    expect_out=["Mainline"],
)

case("a tree with no TOC at all fails", 1, {}, BASE_LUAS)

case(
    "a tree with no retail TOC fails",
    1,
    {VANILLA: copy.deepcopy(GOOD[VANILLA])},
    BASE_LUAS,
)


def main():
    failures = []
    for name, expected, tocs, luas, gitignore, expect_out in CASES:
        print(f"--- {name}")
        got, out = run(tocs, luas, gitignore)
        bad = []
        if got != expected:
            bad.append(f"expected exit {expected}, got {got}")
        for needle in expect_out or []:
            if needle not in out:
                bad.append(f"output missing {needle!r}")
        if bad:
            for b in bad:
                print(f"FAIL: {b}")
            print(out.rstrip())
            failures.append(name)
        else:
            print(f"ok: exit {got}")
    print()
    if failures:
        for name in failures:
            print(f"FAILED: {name}")
        print(f"{len(failures)} of {len(CASES)} case(s) failed")
        return 1
    print(f"all {len(CASES)} cases passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
