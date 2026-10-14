#!/usr/bin/env python3
"""Assert that core.md section 12 Coverage and the suite's notCovered list name the same sections.

The Coverage paragraph of core.md section 12 names the normative requirements
that no conformance fixture exercises, each by its section (`§3.3`). The
atx-conformance suite indexes the same gaps in the `notCovered` list of its
`conformance.json`, each item citing its core.md section ("ATX core.md section
3.3"). The two are kept in different repositories, so they drift: the suite
added a §3.1 item and the paragraph did not name §3.1.

This check compares the two sets of sections the way the family spec-drift
check `notcovered-index-agrees-with-spec` does, so it can be run with only the
suite checked out:

    python3 scripts/check_coverage_index.py --suite <path-to-atx-conformance> [--root <tree>]

A notCovered item that cites no section fails, as does a section one side names
and the other does not. Only the line that opens with `**Coverage.**` is read,
as the family check reads it, so the paragraph stays on one line. A missing
section 12, Coverage paragraph, conformance.json or notCovered list also fails,
so a renamed anchor cannot pass vacuously. Each failure is reported as
file:line with its rule in brackets.

Exit 0 when the two sets are equal, 1 otherwise.
"""

import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

HOME_FILE = "core.md"
HEADING_RE = re.compile(r"^## 12\. Conformance")
NEXT_HEADING_RE = re.compile(r"^## ")
ANCHOR_RE = re.compile(r"^\*\*Coverage\.\*\*")
HOME_CITE_RE = re.compile(r"§(\d+(?:\.\d+)*)")
ITEM_CITE_RE = re.compile(r"[Ss]ection (\d+(?:\.\d+)*)")


def coverage_line(lines):
    """(index, text) of the Coverage paragraph inside section 12, or None."""
    start = next((i for i, line in enumerate(lines) if HEADING_RE.match(line)), None)
    if start is None:
        return None
    for i in range(start + 1, len(lines)):
        if NEXT_HEADING_RE.match(lines[i]):
            break
        if ANCHOR_RE.match(lines[i]):
            return i, lines[i]
    return None


def section_key(cite):
    return tuple(int(part) for part in cite.split("."))


def check(root, suite):
    failures = []
    home = root / HOME_FILE
    if not home.is_file():
        return [f"{HOME_FILE} [coverage] file not found"]
    found = coverage_line(home.read_text(encoding="utf-8").splitlines())
    if found is None:
        return [f"{HOME_FILE} [coverage] no line opening with **Coverage.** in section 12, Conformance"]
    index, para = found
    where = f"{HOME_FILE}:{index + 1}"
    home_cites = set(HOME_CITE_RE.findall(para))

    index_file = suite / "conformance.json"
    if not index_file.is_file():
        return [f"conformance.json [notCovered] not found under {suite}"]
    try:
        items = json.loads(index_file.read_text(encoding="utf-8")).get("notCovered")
    except (ValueError, AttributeError) as exc:
        return [f"conformance.json [notCovered] not a JSON object: {exc}"]
    if not isinstance(items, list) or not items:
        return ["conformance.json [notCovered] no notCovered list, or an empty one"]

    seen = set()
    for n, entry in enumerate(items):
        text = entry.get("item") if isinstance(entry, dict) else None
        cites = set(ITEM_CITE_RE.findall(text)) if isinstance(text, str) else set()
        if not cites:
            failures.append(
                f"conformance.json notCovered[{n}] [uncited] the item cites no core.md section: "
                f"{str(text)[:80]!r}"
            )
        seen |= cites

    for c in sorted(home_cites - seen, key=section_key):
        failures.append(
            f"{where} [coverage] the Coverage paragraph names §{c} as uncovered; "
            f"no notCovered item cites section {c}"
        )
    for c in sorted(seen - home_cites, key=section_key):
        failures.append(
            f"{where} [coverage] notCovered cites section {c}; the Coverage paragraph does not name §{c}"
        )
    return failures


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--suite", required=True, help="path to a checkout of opena2a-standards/atx-conformance")
    ap.add_argument("--root", default=str(ROOT), help="tree to check (default: this repository)")
    args = ap.parse_args()

    failures = check(pathlib.Path(args.root).resolve(), pathlib.Path(args.suite).resolve())
    if failures:
        print("core.md section 12 Coverage and the suite's notCovered list disagree:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        print(
            "\nName every section a notCovered item cites in the Coverage paragraph, and give "
            "every notCovered item its core.md section.",
            file=sys.stderr,
        )
        return 1

    print("coverage index ok: the Coverage paragraph and notCovered name the same sections")
    return 0


if __name__ == "__main__":
    sys.exit(main())
