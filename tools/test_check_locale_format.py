#!/usr/bin/env python3
"""Prove check_locale_format.py fires on each drift shape, and stays quiet on a good tree.

Deriving the locale list from the TOC moves the staleness rather than deleting it - the
derivation itself can come up short - so every case expecting a FAIL asserts the same thing:
a locale which is not checked is LOUD, never a quiet zero.

Each case is followed by a MUTATION that edits the gate's SOURCE and asserts the case flips,
because a check written against a gate can pass without being able to fail. Run as:

    python tools/test_check_locale_format.py           # cases only
    python tools/test_check_locale_format.py mutate    # cases, then the mutation pass

Builds throwaway trees under a temp directory, so it never touches the real checkout.
"""
import importlib.util
import io
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
GATE = HERE / "check_locale_format.py"

sys.path.insert(0, str(HERE))
import check_locale_format  # noqa: E402

TOC_NAME = "EverythingQuests.toc"

HEADER = (
    "## Interface: 120100\n"
    "## Title: Everything Quests\n"
    "## Version: 1.43.1\n"
    "\n"
    "# Locales\n"
)

TOC_LOCALES = ["enUS", "frFR", "ruRU", "koKR", "zhCN", "zhTW", "deDE"]

CLEAN = {
    'L["Version %s"] = "Version %s"': None,
    'L["Hide tracker in combat"] = "Masquer en combat"': None,
}


def build(tmp, toc_locales, files, toc_present=True, toc_body=None):
    """toc_locales names what the TOC LISTS, files names what is ON DISK - they are
    deliberately separate so a drift between them can be constructed."""
    root = Path(tmp)
    (root / "Locales").mkdir(parents=True, exist_ok=True)
    for loc, entries in files.items():
        body = "local _, ns = ...\nlocal L = ns.L\n"
        body += "".join(line + "\n" for line in entries)
        (root / "Locales" / f"{loc}.lua").write_text(body, encoding="utf-8")
    if toc_present:
        if toc_body is None:
            toc_body = HEADER + "".join(f"Locales\\{loc}.lua\n" for loc in toc_locales)
        (root / TOC_NAME).write_text(toc_body, encoding="utf-8")
    return root


def run(module, toc_locales, files, toc_present=True, toc_body=None):
    with tempfile.TemporaryDirectory() as tmp:
        root = build(tmp, toc_locales, files, toc_present, toc_body)
        old_root, old_toc = module.ROOT, module.TOC
        module.ROOT, module.TOC = root, root / TOC_NAME
        try:
            buf = io.StringIO()
            with redirect_stdout(buf):
                code = module.main()
            return code, buf.getvalue()
        finally:
            module.ROOT, module.TOC = old_root, old_toc


CASES = []


def case(name, expected, toc_locales, files, toc_present=True, toc_body=None,
         expect_out=None, reject_out=None):
    CASES.append((name, expected, toc_locales, files, toc_present, toc_body,
                  expect_out, reject_out))


def good_files(extra=None):
    files = {loc: list(CLEAN) for loc in TOC_LOCALES}
    if extra:
        files.update(extra)
    return files



case("a clean tree with all six translations passes", 0, TOC_LOCALES, good_files(),
     expect_out=["TOTAL FAIL across all locales: 0", "checked 6 locale(s)",
                 "deDE", "zhTW"])

case("enUS is the manifest and is not checked as a translation", 0, TOC_LOCALES, good_files(),
     reject_out=["===== enUS"])

case("a positional specifier is correct, not a failure", 0, TOC_LOCALES,
     good_files({"ruRU": ['L["%s took %d damage"] = "%2$d urona nanes %1$s"']}),
     expect_out=["TOTAL FAIL across all locales: 0"])

case("dropping the key's trailing plural %s is a NOTE, not a FAIL", 0, TOC_LOCALES,
     good_files({"koKR": ['L["added %d quest%s"] = "%d gae chuga"']}),
     expect_out=["TOTAL FAIL across all locales: 0",
                 "NOTE (unused arguments, not an error): 1"])



case("a translation on disk the TOC never loads FAILS", 1,
     [loc for loc in TOC_LOCALES if loc != "deDE"], good_files(),
     expect_out=["FAIL", "deDE"])

case("a locale the TOC lists but that is missing from disk FAILS", 1, TOC_LOCALES,
     {loc: list(CLEAN) for loc in TOC_LOCALES if loc != "zhTW"},
     expect_out=["FAIL", "zhTW"])

case("a TOC that lists no Locales files at all FAILS rather than checking zero", 1, TOC_LOCALES,
     good_files(), toc_body=HEADER + "Core\\Init.lua\n",
     expect_out=["FAIL", "lists no Locales"])

case("a missing TOC FAILS rather than checking zero", 1, TOC_LOCALES, good_files(),
     toc_present=False, expect_out=["FAIL", "cannot derive"])

case("a TOC listing only enUS FAILS - there is nothing to compare", 1, ["enUS"],
     {"enUS": list(CLEAN)},
     expect_out=["FAIL", "no translated locale"])

case("a TOC that does not list enUS FAILS - it is reading the wrong thing", 1,
     [loc for loc in TOC_LOCALES if loc != "enUS"],
     {loc: list(CLEAN) for loc in TOC_LOCALES if loc != "enUS"},
     expect_out=["FAIL", "does not list"])



case("an invalid specifier FAILS", 1, TOC_LOCALES,
     good_files({"frFR": ['L["Level %d"] = "Niveau %z"']}),
     expect_out=["invalid specifier", "TOTAL FAIL across all locales: 1"])

case("a bare % the translator meant as a word FAILS", 1, TOC_LOCALES,
     good_files({"koKR": ['L["Scale"] = "bigyul (%)"']}),
     expect_out=["invalid specifier"])

case("using an argument the key does not supply FAILS", 1, TOC_LOCALES,
     good_files({"zhCN": ['L["Version %s"] = "%1$s ban %2$d"']}),
     expect_out=["but the key supplies only"])

case("a numeric conversion where the key passes a string FAILS", 1, TOC_LOCALES,
     good_files({"deDE": ['L["Version %s"] = "Version %d"']}),
     expect_out=["the key passes a string"])

case("mixing positional and plain specifiers in one string FAILS", 1, TOC_LOCALES,
     good_files({"ruRU": ['L["%s at %s"] = "%1$s v %s"']}),
     expect_out=["mixes positional and plain"])

case("an L[...] line the parser cannot read FAILS instead of passing silently", 1, TOC_LOCALES,
     good_files({"zhTW": ['L["Version %s"] = "Ban %s" -- trailing']}),
     expect_out=["could not read", "NOT checked"])


def evaluate(module, spec):
    name, expected, toc_locales, files, toc_present, toc_body, expect_out, reject_out = spec
    got, out = run(module, toc_locales, files, toc_present, toc_body)
    bad = []
    if got != expected:
        bad.append(f"expected exit {expected}, got {got}")
    for needle in expect_out or []:
        if needle not in out:
            bad.append(f"output missing {needle!r}")
    for needle in reject_out or []:
        if needle in out:
            bad.append(f"output should not contain {needle!r}")
    return bad, out


# Each entry disables one guard in the gate's source and names the case that MUST go red.
# A mutation that does not apply, or whose mutant will not import, is a FAILURE of this
# harness and not a pass - a check written against a gate can otherwise never fail.

MUTATIONS = [
    ("stop reporting a translation the TOC never loads",
     "    if unlisted:",
     "    if False:",
     "a translation on disk the TOC never loads FAILS"),
    ("accept a TOC that lists no Locales files",
     "    if not listed:",
     "    if False and not listed:",
     "a TOC that lists no Locales files at all FAILS rather than checking zero"),
    ("stop noticing the TOC is not the one that lists enUS",
     "    if MANIFEST_LOCALE not in listed:",
     "    if False:",
     "a TOC that does not list enUS FAILS - it is reading the wrong thing"),
    ("stop counting a listed locale whose file is missing",
     '            print(f"\\n===== {loc} =====\\n  FAIL: {TOC.name} lists it but {path} is missing")\n'
     "            total_fail += 1",
     '            print(f"\\n===== {loc} =====\\n  FAIL: {TOC.name} lists it but {path} is missing")\n'
     "            total_fail += 0",
     "a locale the TOC lists but that is missing from disk FAILS"),
    ("check enUS as if it were a translation",
     "    locales = [loc for loc in listed if loc != MANIFEST_LOCALE]",
     "    locales = list(listed)",
     "enUS is the manifest and is not checked as a translation"),
    ("stop counting L[...] lines the parser could not read",
     "            total_fail += skipped",
     "            total_fail += 0",
     "an L[...] line the parser cannot read FAILS instead of passing silently"),
    ("stop rejecting an invalid conversion character",
     "        if conv not in VALID:",
     "        if False and conv not in VALID:",
     "an invalid specifier FAILS"),
    ("stop rejecting a % the specifier pattern never consumed",
     "            bad.append(stripped[pos:pos + 3])",
     "            pass",
     "a bare % the translator meant as a word FAILS"),
]


def load_mutant(source, tmpdir):
    path = Path(tmpdir) / "mutant_check_locale_format.py"
    path.write_text(source, encoding="utf-8")
    spec = importlib.util.spec_from_file_location("mutant_check_locale_format", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def mutate():
    original = GATE.read_text(encoding="utf-8")
    by_name = {spec[0]: spec for spec in CASES}
    failures = []
    print("\n--- mutation pass ---")
    for label, old, new, case_name in MUTATIONS:
        print(f"\nmutation: {label}")
        if old not in original:
            print(f"  FAIL: the mutation does not apply - {old!r} is not in the gate")
            failures.append(label)
            continue
        spec = by_name.get(case_name)
        if spec is None:
            print(f"  FAIL: no case named {case_name!r} to check against")
            failures.append(label)
            continue
        mutated = original.replace(old, new, 1)
        with tempfile.TemporaryDirectory() as tmp:
            try:
                module = load_mutant(mutated, tmp)
            except Exception as err:  # a mutant that will not import proves nothing
                print(f"  FAIL: the mutated source did not import - {err}")
                failures.append(label)
                continue
            bad, _out = evaluate(module, spec)
        if bad:
            print(f"  ok: {case_name!r} went red - {bad[0]}")
        else:
            print(f"  FAIL: VACUOUS - {case_name!r} still passed with the guard removed")
            failures.append(label)
    print()
    if failures:
        for label in failures:
            print(f"FAILED MUTATION: {label}")
        print(f"{len(failures)} of {len(MUTATIONS)} mutation(s) did not flip")
        return 1
    print(f"all {len(MUTATIONS)} mutations flipped")
    return 0


def main():
    failures = []
    for spec in CASES:
        name = spec[0]
        print(f"\ncase: {name}")
        bad, out = evaluate(check_locale_format, spec)
        if bad:
            for b in bad:
                print(f"FAIL: {b}")
            print(out.rstrip())
            failures.append(name)
        else:
            print(f"ok: exit {spec[1]}")
    print()
    if failures:
        for name in failures:
            print(f"FAILED: {name}")
        print(f"{len(failures)} of {len(CASES)} case(s) failed")
        return 1
    print(f"all {len(CASES)} cases passed")

    if len(sys.argv) > 1 and sys.argv[1] == "mutate":
        return mutate()
    return 0


if __name__ == "__main__":
    sys.exit(main())
