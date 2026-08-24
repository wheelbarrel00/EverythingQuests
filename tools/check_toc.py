#!/usr/bin/env python3
"""Guard against TOC drift across Everything Quests' per-flavor TOC files.

Separate per-flavor TOCs are what let a git checkout run in-game with no build step, but
they cost one file list per flavor to keep in sync. This checks six things:

  1. every path referenced by any TOC exists on disk
  2. every authored .lua and .xml under SOURCE_DIRS is referenced by at least one TOC, so
     adding Core/Foo.lua and forgetting to list it is caught
  3. the retail TOCs (the base one and _Mainline, if it ever exists) list exactly the same
     files, checked in both directions, so they cannot drift apart
  4. every flavor TOC lists every file the retail TOC lists, unless that omission is
     DECLARED in the flavor TOC itself
  5. '## Version:' and '## X-Curse-Project-ID:' agree across every TOC
  6. every TOC name ends in a suffix the packager actually recognizes

Check 4 is the reason this file exists rather than a copy of the sibling addon's gate. That
one anchors coverage on "listed by at least one TOC" and exempts flavor TOCs deliberately,
so a flavor TOC omitting a shared file is legal there by design and its suite asserts as
much. The cost is that an omission nobody intended looks exactly like one somebody chose.
Here coverage is the default and every hole has to be named, which separates the two.

Three directives, written as comments in a TOC:

  # check-toc: scaffold        the whole TOC is exempt from check 4. For a TOC that loads
                               a probe and nothing else. The missing count is still
                               REPORTED every run, so the gap cannot go quiet.
  # check-toc: omit <path>     one declared omission, for a file that flavor genuinely
                               cannot run. Stale directives are an error, or the
                               exemptions rot into a second place coverage hides.
  # check-toc: flavor-only <path>
                               that file is listed by flavor TOCs only, never a retail one.
                               It satisfies check 2 without a retail listing.

Flavor TOCs may list files no retail TOC has - a Classic-only quest database is the obvious
case. Locally check 2 covers those, because the flavor TOC listing them is on disk. In CI it
does NOT: .gitignore hides the flavor TOCs, actions/checkout never materializes them, and
the file reads as listed by nothing. That is what flavor-only declares, and it therefore has
to live in a TRACKED TOC - declaring it in a gitignored one is an error, because CI would
never read the directive either.

Its own coverage is not waived, only moved: on a tree that has a flavor TOC, at least one
must actually list the file. Where no flavor TOC is on disk it is reported as NOT CHECKED by
name, alongside the TOCs themselves.

The packager copies the whole checkout, so a flavor-only file ships inside the retail zip
too. It costs disk there and nothing else - no retail TOC loads it.

TOCs that .gitignore hides are reported as NOT CHECKED when they are absent from disk, so
a green run in CI or on a fresh clone can never read as "the flavor TOCs were verified".

Run locally or in CI. Exits non-zero on any problem. tools/test_check_toc.py proves it
fires on each of these shapes and stays quiet on a good tree.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIRS = ("Locales", "Core", "Modules", "Data", "Options")
SOURCE_SUFFIXES = (".lua", ".xml")
ADDON = "EverythingQuests"
SHARED_HEADERS = ("Version", "X-Curse-Project-ID")

# The packager derives a game version from the suffix. One it does not recognize is not an
# error there, it is silently treated as another retail TOC, so it has to be an error here.
RETAIL_SUFFIXES = ("", "Mainline")
FLAVOR_SUFFIXES = ("Classic", "Vanilla", "TBC", "Wrath", "Cata", "Mists")

_HEADER = re.compile(r"^##\s*([^:]+):\s*(.*?)\s*$")
_DIRECTIVE = re.compile(r"^#\s*check-toc:\s*(\S+)\s*(.*?)\s*$")


def parse_toc(toc: Path):
    files, headers, scaffold, omits, flavor_only = [], {}, False, [], []
    for raw in toc.read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("##"):
            m = _HEADER.match(line)
            if m:
                headers[m.group(1).strip()] = m.group(2)
            continue
        if line.startswith("#"):
            m = _DIRECTIVE.match(line)
            if m:
                verb, arg = m.group(1).lower(), m.group(2)
                if verb == "scaffold":
                    scaffold = True
                elif verb == "omit" and arg:
                    omits.append(arg.replace("\\", "/"))
                elif verb == "flavor-only" and arg:
                    flavor_only.append(arg.replace("\\", "/"))
            continue
        files.append(line.replace("\\", "/"))
    return {"files": files, "headers": headers, "scaffold": scaffold, "omits": omits,
            "flavor_only": flavor_only}


def suffix_of(name: str) -> str:
    stem = name[: -len(".toc")]
    if stem == ADDON:
        return ""
    if stem.startswith(ADDON + "_"):
        return stem[len(ADDON) + 1:]
    return stem


def gitignored_tocs(root: Path):
    gitignore = root / ".gitignore"
    if not gitignore.is_file():
        return []
    names = []
    for raw in gitignore.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line and not line.startswith("#") and line.endswith(".toc"):
            names.append(line)
    return names


def main(root: Path = ROOT) -> int:
    root = Path(root)
    tocs = sorted(root.glob("*.toc"))
    if not tocs:
        print("error: no .toc files found at repo root")
        return 1

    problems, notices = [], []
    parsed = {t.name: parse_toc(t) for t in tocs}

    for name in sorted(parsed):
        for rel in parsed[name]["files"]:
            if not (root / rel).is_file():
                problems.append(f"{name}: references missing file {rel}")

    for field in SHARED_HEADERS:
        seen = {}
        for name in sorted(parsed):
            seen.setdefault(parsed[name]["headers"].get(field), []).append(name)
        if len(seen) > 1:
            detail = "; ".join(
                f"{value!r} in {', '.join(names)}"
                for value, names in sorted(seen.items(), key=lambda kv: str(kv[0]))
            )
            problems.append(f"## {field}: disagrees across TOCs - {detail}")

    retail, flavor = [], []
    for name in sorted(parsed):
        sfx = suffix_of(name)
        if sfx in RETAIL_SUFFIXES:
            retail.append(name)
        elif sfx in FLAVOR_SUFFIXES:
            flavor.append(name)
        else:
            known = ", ".join(FLAVOR_SUFFIXES + tuple(s for s in RETAIL_SUFFIXES if s))
            problems.append(
                f"{name}: suffix {sfx!r} is not one the packager recognizes - "
                f"expected one of {known} or no suffix")

    if not retail:
        problems.append(
            f"missing the retail TOC {ADDON}.toc - every other check anchors on it")

    hidden_tocs = gitignored_tocs(root)
    hidden = set(hidden_tocs)
    flavor_only = {}
    for name in sorted(parsed):
        for rel in parsed[name]["flavor_only"]:
            flavor_only.setdefault(rel, []).append(name)

    for rel, declared_in in sorted(flavor_only.items()):
        where = ", ".join(declared_in)
        if not (root / rel).is_file():
            problems.append(
                f"stale '# check-toc: flavor-only {rel}' in {where} - no such file on disk")
            continue
        in_retail = [n for n in retail if rel in parsed[n]["files"]]
        if in_retail:
            problems.append(
                f"stale '# check-toc: flavor-only {rel}' in {where} - "
                f"{', '.join(in_retail)} lists it, so it is not flavor only")
        # A directive CI cannot read is worse than none: the file still fails coverage there,
        # and the tree looks reviewed.
        if all(n in hidden for n in declared_in):
            target = retail[0] if retail else f"{ADDON}.toc"
            problems.append(
                f"'# check-toc: flavor-only {rel}' is declared only in {where}, which "
                f".gitignore hides - CI never reads it. Declare it in {target}")
        in_flavor = [n for n in flavor if rel in parsed[n]["files"]]
        if in_flavor:
            notices.append(f"{rel}: FLAVOR-ONLY - listed by {', '.join(in_flavor)}")
        elif flavor:
            problems.append(
                f"'# check-toc: flavor-only {rel}' but no flavor TOC on disk lists it - "
                f"list it in one, or drop the file and the directive")
        else:
            notices.append(
                f"{rel}: FLAVOR-ONLY, NOT CHECKED - no flavor TOC is on disk here, so "
                f"nothing proves any TOC lists it")

    anywhere = set(flavor_only)
    for name in parsed:
        anywhere.update(parsed[name]["files"])
    for d in SOURCE_DIRS:
        src = root / d
        if not src.is_dir():
            continue
        for path in sorted(src.rglob("*")):
            if path.suffix.lower() not in SOURCE_SUFFIXES or not path.is_file():
                continue
            rel = path.relative_to(root).as_posix()
            if rel not in anywhere:
                problems.append(f"no TOC lists {rel}")

    # The retail TOCs must stay in step with each other in both directions. Before a second
    # one exists they are byte-identical by definition, which is the only reason a one-sided
    # edit has never been caught.
    if len(retail) > 1:
        base = retail[0]
        for other in retail[1:]:
            a, b = set(parsed[base]["files"]), set(parsed[other]["files"])
            for rel in sorted(b - a):
                problems.append(f"{other}: lists {rel}, which {base} does not")
            for rel in sorted(a - b):
                problems.append(f"{base}: lists {rel}, which {other} does not")

    if retail:
        reference = retail[0]
        expected = parsed[reference]["files"]
        for name in flavor:
            spec = parsed[name]
            listed = set(spec["files"])
            missing = [rel for rel in expected if rel not in listed]

            for rel in spec["omits"]:
                if rel in listed:
                    problems.append(
                        f"{name}: stale '# check-toc: omit {rel}' - the TOC lists that file")
                elif rel not in expected:
                    problems.append(
                        f"{name}: stale '# check-toc: omit {rel}' - {reference} does not "
                        f"list that file, so there is nothing to exempt")

            if spec["scaffold"]:
                notices.append(
                    f"{name}: SCAFFOLD - coverage NOT enforced, {len(missing)} of "
                    f"{len(expected)} file(s) in {reference} are unlisted")
                continue

            declared = set(spec["omits"])
            for rel in missing:
                if rel not in declared:
                    problems.append(
                        f"{name}: does not list {rel}, which {reference} does - list it, or "
                        f"declare '# check-toc: omit {rel}' in {name}")
            if declared:
                notices.append(
                    f"{name}: {len(declared)} declared omission(s) - "
                    f"{', '.join(sorted(declared))}")

    for name in hidden_tocs:
        if name not in parsed:
            notices.append(
                f"{name}: NOT CHECKED - .gitignore hides it and it is not on disk here")
        else:
            notices.append(
                f"{name}: checked locally, but .gitignore hides it so CI never sees it")

    for n in notices:
        print(f"note: {n}")
    if problems:
        for p in problems:
            print(f"error: {p}")
        return 1

    counts = ", ".join(f"{name}={len(parsed[name]['files'])}" for name in sorted(parsed))
    print(f"TOC check passed ({counts})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
