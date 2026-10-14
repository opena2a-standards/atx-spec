#!/usr/bin/env python3
"""Assert the conformance-suite fixture counts stated here match the suite.

README.md, docs/conformance.md and core.md (section 12) each state how many
fixtures the atx-conformance suite ships, and docs/conformance.md restates the
pass count the reference verifiers report. Those are measurements taken in
another repository, so they are checked here rather than maintained by hand:
the count drifted to 18 while the suite shipped 20 and nothing caught it.

This repository does not contain the fixtures, so the suite is supplied by the
caller:

    python3 scripts/check_conformance_counts.py --suite <path-to-atx-conformance>

CI checks out opena2a-standards/atx-conformance at main and passes it here. The
ref is deliberately main and not a pinned SHA: the drift being caught is exactly
"the suite moved and the spec did not", and a pinned ref would reproduce the bug.

Exit 0 when every stated count matches the suite, 1 otherwise.
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Files that state a fixture count, and a human pointer to where.
CLAIM_FILES = {
    "README.md": "the reference verifier's summary line under the first use case",
    "docs/conformance.md": "the conformance-suite paragraph",
    "core.md": "section 12, Conformance",
}


def stated_counts(text):
    """Every fixture/pass count asserted in one document.

    Matches the phrasings actually used:
      "The suite ships 18 fixtures"
      "18 fixtures (baseline, hybrid, ...)"
      "Both verifiers report 18 of 18 PASS"
    """
    found = []
    for m in re.finditer(r"\b(\d+)\s+fixtures\b", text):
        found.append(("fixtures", int(m.group(1)), m.start()))
    for m in re.finditer(r"\b(\d+)\s+of\s+(\d+)\s+PASS\b", text):
        found.append(("pass", int(m.group(1)), m.start()))
        found.append(("of", int(m.group(2)), m.start()))
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--suite",
        required=True,
        help="path to a checkout of opena2a-standards/atx-conformance",
    )
    args = ap.parse_args()

    fixtures_dir = pathlib.Path(args.suite) / "fixtures"
    if not fixtures_dir.is_dir():
        print(f"no fixtures/ directory under {args.suite}", file=sys.stderr)
        return 1

    actual = len(sorted(fixtures_dir.glob("*.json")))
    if actual == 0:
        print("suite reports 0 fixtures; refusing to pass vacuously", file=sys.stderr)
        return 1

    failures = []
    checked = 0

    for name, where in CLAIM_FILES.items():
        path = ROOT / name
        if not path.exists():
            failures.append(f"{name} is missing")
            continue
        claims = stated_counts(path.read_text(encoding="utf-8"))
        if not claims:
            failures.append(
                f"{name} states no fixture count ({where}); the guard would pass "
                f"vacuously, so this is a failure"
            )
            continue
        for kind, value, offset in claims:
            checked += 1
            if value != actual:
                line = path.read_text(encoding="utf-8")[:offset].count("\n") + 1
                failures.append(
                    f"{name}:{line} states {value} ({kind}) but the suite ships {actual}"
                )

    if failures:
        print("conformance counts are stale:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        print(
            f"\natx-conformance ships {actual} fixtures. Update the count in "
            f"{', '.join(CLAIM_FILES)} and note it in CHANGELOG.md.",
            file=sys.stderr,
        )
        return 1

    print(
        f"conformance counts match: {actual} fixtures, "
        f"{checked} stated value(s) checked across {len(CLAIM_FILES)} documents"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
