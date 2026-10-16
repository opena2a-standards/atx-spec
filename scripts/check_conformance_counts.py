#!/usr/bin/env python3
"""Assert the conformance-suite fixture counts stated here match the suite.

README.md, docs/conformance.md and core.md (section 12) each state how many
fixtures the atx-conformance suite ships, docs/conformance.md restates the
pass count the reference verifiers report, and the reference verifier's
summary line in README.md states its pass and fail counts. Those are
measurements taken in another repository, so they are checked here rather than
maintained by hand: the count drifted to 18 while the suite shipped 20 and
nothing caught it. A stated pass count must equal the number of fixtures and a
stated fail count must be 0.

This repository does not contain the fixtures, so the suite is supplied by the
caller:

    python3 scripts/check_conformance_counts.py --suite <path-to-atx-conformance> [--root <tree>]

--root names the tree whose README.md, docs/conformance.md and core.md are read
(default: this repository); scripts/test_conformance_counts.sh uses it on
scratch trees.

CI checks out opena2a-standards/atx-conformance at main and passes it here. The
ref is deliberately main and not a pinned SHA: the drift being caught is exactly
"the suite moved and the spec did not", and a pinned ref would reproduce the bug.

Exit 0 when every stated count matches the suite, 1 otherwise.
"""

import argparse
import bisect
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


# A word that may sit between the count and "fixtures" and still describe the
# whole suite. A count with any other word there ("three hybrid fixtures") is a
# subset of the suite, so it is not compared with the suite's size.
WHOLE_SUITE_QUALIFIERS = ("byte-pinned", "pinned", "shipped", "conformance")

FIXTURES_RE = re.compile(
    r"\b(\d+)\s+(?:(?:" + "|".join(map(re.escape, WHOLE_SUITE_QUALIFIERS)) + r")\s+)?fixtures\b"
)
OF_PASS_RE = re.compile(r"\b(\d+)\s+of\s+(\d+)\s+PASS\b")
SUMMARY_RE = re.compile(r"\b(\d+)\s+pass,\s+(\d+)\s+fail\b")
NEWLINE_RE = re.compile(r"\n")


def line_of(newlines, offset):
    """The line offset sits on, found by bisecting where each newline of its
    text stands. Counting newlines from the start of the file for each stale
    count took time quadratic in the number of stale counts."""
    return bisect.bisect_left(newlines, offset) + 1


def stated_counts(text):
    """Every fixture/pass/fail count asserted in one document.

    Matches the phrasings actually used:
      "The suite ships 18 fixtures"
      "ships 18 byte-pinned fixtures"
      "18 fixtures (baseline, hybrid, ...)"
      "Both verifiers report 18 of 18 PASS"
      "# summary: 18 pass, 0 fail (18 fixtures)"  (the Go reference verifier's last line)
    """
    found = []
    for m in FIXTURES_RE.finditer(text):
        found.append(("fixtures", int(m.group(1)), m.start()))
    for m in OF_PASS_RE.finditer(text):
        found.append(("pass", int(m.group(1)), m.start()))
        found.append(("of", int(m.group(2)), m.start()))
    for m in SUMMARY_RE.finditer(text):
        found.append(("pass", int(m.group(1)), m.start()))
        found.append(("fail", int(m.group(2)), m.start()))
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--suite",
        required=True,
        help="path to a checkout of opena2a-standards/atx-conformance",
    )
    ap.add_argument("--root", default=str(ROOT), help="tree to check (default: this repository)")
    args = ap.parse_args()
    root = pathlib.Path(args.root).resolve()

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
        path = root / name
        if not path.exists():
            failures.append(f"{name} is missing")
            continue
        text = path.read_text(encoding="utf-8")
        claims = stated_counts(text)
        if not claims:
            failures.append(
                f"{name} states no fixture count ({where}); the guard would pass "
                f"vacuously, so this is a failure"
            )
            continue
        newlines = [m.start() for m in NEWLINE_RE.finditer(text)]
        for kind, value, offset in claims:
            checked += 1
            # A run that passes every fixture reports no failures.
            expected = 0 if kind == "fail" else actual
            if value != expected:
                line = line_of(newlines, offset)
                if kind == "fail":
                    failures.append(
                        f"{name}:{line} states {value} ({kind}) but a run that passes "
                        f"all {actual} fixtures reports 0"
                    )
                else:
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
