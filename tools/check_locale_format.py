#!/usr/bin/env python3
"""Format-specifier parity check for every translated locale.

WoW's string.format supports Blizzard's positional extension (%1$s, %2$d), and
docs/LOCALIZATION.md tells translators to use it when word order has to change. So a
value is compared by ARGUMENT INDEX against its English key, not by a flat specifier list.

  FAIL  - raises at runtime in that language only:
            * an invalid specifier
            * a reference to an argument index the key does not supply
            * a numeric conversion where the key passes a string
            * positional and plain specifiers mixed in one string
  NOTE  - the value uses fewer of the key's arguments than the key does. Legitimate and
          common: Russian and Korean have no use for English's "%s" plural suffix.

The locale list is READ FROM THE TOC rather than hardcoded, and every way that derivation
can come up short is a FAIL here, never a quiet zero.

Exit code 1 if any FAIL is found, 0 otherwise.
"""
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")

ROOT = Path(__file__).resolve().parent.parent
TOC = ROOT / "EverythingQuests.toc"

# enUS is the manifest that creates ns.L, not a translation, so it has nothing to compare against
MANIFEST_LOCALE = "enUS"
TOC_LOCALE = re.compile(r"^Locales[\\/](\w+)\.lua\s*$", re.IGNORECASE)

ENTRY = re.compile(r'^L\["(.*)"\]\s*=\s*"(.*)"\s*$')
ANY_ENTRY = re.compile(r"^L\[")
SPEC = re.compile(r"%(?:(\d+)\$)?([-+ #0]*)(\d*)(?:\.(\d+))?([a-zA-Z])")
# %c takes a number in Lua 5.1, so it belongs with the numeric conversions
NUMERIC = set("diouxXeEfgGc")
VALID = set("diouxXeEfgGqsc")


def locales_from_toc(toc_path):
    """A locale the TOC lists but is not on disk, or a file on disk the TOC never loads, is
    a problem rather than a silent skip."""
    problems = []
    if not toc_path.exists():
        return [], [f"cannot derive the locale list: {toc_path} is missing"]

    listed = []
    for line in toc_path.read_text(encoding="utf-8-sig").splitlines():
        m = TOC_LOCALE.match(line.strip())
        if m:
            listed.append(m.group(1))

    if not listed:
        return [], [f"{toc_path.name} lists no Locales/*.lua files at all"]
    if MANIFEST_LOCALE not in listed:
        problems.append(f"{toc_path.name} does not list Locales/{MANIFEST_LOCALE}.lua, "
                        "so the derivation is reading the wrong thing")

    locales = [loc for loc in listed if loc != MANIFEST_LOCALE]
    if not locales:
        problems.append(f"{toc_path.name} lists no translated locale beyond {MANIFEST_LOCALE}")

    on_disk = sorted(p.stem for p in (ROOT / "Locales").glob("*.lua")
                     if p.stem != MANIFEST_LOCALE)
    unlisted = [loc for loc in on_disk if loc not in locales]
    if unlisted:
        problems.append("translation file(s) on disk that the retail TOC never loads: "
                        + ", ".join(unlisted))
    return locales, problems


def parse(fmt):
    args, bad = {}, []
    positional = plain = 0
    nxt = 1
    stripped = fmt.replace("%%", "")
    consumed = set()
    for m in SPEC.finditer(stripped):
        idx, _flags, width, prec, conv = m.groups()
        consumed.add(m.start())
        if conv not in VALID:
            bad.append(m.group(0))
            continue
        # Lua 5.1 rejects a width or precision longer than two digits
        if len(width or "") > 2 or len(prec or "") > 2:
            bad.append(m.group(0))
            continue
        if idx:
            positional += 1
            i = int(idx)
        else:
            plain += 1
            i = nxt
            nxt += 1
        args[i] = conv
    # Any '%' the specifier pattern did not consume is a malformed escape - '%$d', a stray
    # '%z', or a lone trailing '%' where the translator meant '%%'. Lua raises on all three
    for pos, ch in enumerate(stripped):
        if ch == "%" and pos not in consumed:
            bad.append(stripped[pos:pos + 3])
    return args, positional, plain, bad


def check(key, val):
    fails, notes = [], []
    kargs, _kp, _kn, kbad = parse(key)
    vargs, vpos, vplain, vbad = parse(val)

    for b in vbad:
        fails.append(f"invalid specifier {b!r}")
    if kbad:
        fails.append(f"invalid specifier in the ENGLISH KEY: {kbad}")
    if vpos and vplain:
        fails.append("mixes positional and plain specifiers in one string")

    for i, conv in sorted(vargs.items()):
        kconv = kargs.get(i)
        if kconv is None:
            fails.append(f"uses argument {i} (%{conv}) but the key supplies only {len(kargs)}")
        elif conv in NUMERIC and kconv not in NUMERIC:
            fails.append(f"argument {i} is %{conv} but the key passes a string (%{kconv})")

    missing = sorted(set(kargs) - set(vargs))
    if missing and not fails:
        notes.append("does not use argument" + ("s " if len(missing) > 1 else " ")
                     + ", ".join(str(i) for i in missing))
    return fails, notes


def read(path):
    """skipped counts L[...] lines the parser could not read, which would otherwise be
    checked silently and pass."""
    out, skipped = [], 0
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not ANY_ENTRY.match(line):
            continue
        m = ENTRY.match(line)
        if m:
            out.append((m.group(1), m.group(2)))
        else:
            skipped += 1
    return out, skipped


def main():
    total_fail = 0

    locales, problems = locales_from_toc(TOC)
    for p in problems:
        print(f"FAIL: {p}")
        total_fail += 1
    print(f"locales derived from {TOC.name}: {', '.join(locales) if locales else '(none)'}")

    for loc in locales:
        path = ROOT / "Locales" / f"{loc}.lua"
        if not path.exists():
            print(f"\n===== {loc} =====\n  FAIL: {TOC.name} lists it but {path} is missing")
            total_fail += 1
            continue
        entries, skipped = read(path)
        if skipped:
            print(f"\n===== {loc} =====\n  FAIL: {skipped} L[...] line(s) the parser could "
                  f"not read - they were NOT checked. Fix the parser before trusting this run.")
            total_fail += skipped
        failed, noted = [], []
        for key, val in entries:
            fails, notes = check(key, val)
            if fails:
                failed.append((key, val, fails))
            if notes:
                noted.append((key, val, notes))
        total_fail += len(failed)
        print(f"\n===== {loc}  ({len(entries)} entries) =====")
        print(f"  FAIL: {len(failed)}")
        for key, val, why in failed:
            print(f"    ! {key[:70]!r}")
            print(f"      {val[:90]!r}")
            for w in why:
                print(f"      -> {w}")
        print(f"  NOTE (unused arguments, not an error): {len(noted)}")
        for key, val, why in noted:
            print(f"    - {key[:70]!r}  ({'; '.join(why)})")

    print(f"\nchecked {len(locales)} locale(s): "
          f"{', '.join(locales) if locales else '(none)'}")
    print(f"TOTAL FAIL across all locales: {total_fail}")
    if total_fail == 0:
        print("OK - no locale can raise in string.format.")
    return 1 if total_fail else 0


if __name__ == "__main__":
    sys.exit(main())
