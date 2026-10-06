#!/usr/bin/env python3
"""Assert the specification text names no revocation list version counter.

ATP-SPEC v1.0.0-rc1 section 8.1 defines the revocation response as
{ "revocations": [...], "nextSince": "<RFC 3339>" } with additionalProperties
false at both levels. A conforming implementation has nowhere to carry a
version number for its revocation list; the cursor that advances when a
revocation is added is nextSince. Text in this repository that has a node
increment, publish or compare a CRL version therefore asks for something the
wire cannot express.

One rule, checked over every Markdown file in the tree (hidden directories such
as .git and a CI checkout of the conformance suite are skipped):

  crl-version   "CRL version" and "revocation list version" do not appear, in
                any case. The phrase may wrap across lines, since Markdown
                renders a soft line break as a space. Text that needs the
                revocation cursor names nextSince and cites ATP section 8.1.

CHANGELOG.md and errata/ are not checked: they record what earlier text said,
and an erratum quotes the published text verbatim by design.

Each failure is reported as file:line with its rule in brackets.

    python3 scripts/check_revocation_cursor.py [--root <tree>]

Exit 0 when every file passes, 1 otherwise.
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

VERSION_RE = re.compile(r"\b(?:CRL|revocation[\s-]+list)\s+version\b", re.IGNORECASE)
HISTORY = {"CHANGELOG.md"}
HISTORY_DIRS = {"errata"}


def markdown_files(root):
    """Every *.md under root, skipping hidden directories and history, in a stable order."""
    found = []
    for path in sorted(root.rglob("*.md")):
        rel = path.relative_to(root)
        if any(part.startswith(".") for part in rel.parts[:-1]):
            continue
        if "node_modules" in rel.parts:
            continue
        if rel.as_posix() in HISTORY or (len(rel.parts) > 1 and rel.parts[0] in HISTORY_DIRS):
            continue
        found.append(path)
    return found


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def check_file(rel, text):
    return [
        f"{rel}:{line_of(text, m.start())} [crl-version] {' '.join(m.group(0).split())!r} "
        f"cannot be carried by the ATP section 8.1 revocation response; name the "
        f"nextSince cursor instead"
        for m in VERSION_RE.finditer(text)
    ]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(ROOT), help="tree to check (default: this repository)")
    args = ap.parse_args()
    root = pathlib.Path(args.root).resolve()

    files = markdown_files(root)
    if not files:
        print(f"no Markdown files under {root}; refusing to pass vacuously", file=sys.stderr)
        return 1

    failures = []
    for path in files:
        failures.extend(check_file(path.relative_to(root).as_posix(), path.read_text(encoding="utf-8")))

    if failures:
        print("revocation text names a version the wire cannot carry:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print(f"revocation cursor ok: {len(files)} Markdown file(s) checked, none names a CRL version")
    return 0


if __name__ == "__main__":
    sys.exit(main())
