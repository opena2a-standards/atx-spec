#!/usr/bin/env python3
"""Assert how the Markdown documents in this repository name OpenA2A components.

Two rules, checked over every Markdown file in the tree (hidden directories such
as .git and a CI checkout of the conformance suite are skipped):

  first-use     The first occurrence of the whole word AIM in a file is the AIM
                in "OpenA2A AIM (Agent Identity Management)". A bare AIM ahead
                of it, including a link in the navigation bar, fails. An IETF
                working group document defines "Agent Identity Management
                System (AIMS)", so a reader who meets a bare AIM first cannot
                tell the two apart. AIMS is a different word and does not count.

  product-name  ARIA and "trust layer" do not appear as names. Text that needs
                the component says what it does instead (threat research, for
                example). WAI-ARIA, the W3C accessibility specification, is not
                this name and is allowed.

The phrase may wrap across lines, since Markdown renders a soft line break as a
space. Each failure is reported as file:line with its rule in brackets.

    python3 scripts/check_naming.py [--root <tree>]

Exit 0 when every file passes, 1 otherwise.
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

PHRASE = "OpenA2A AIM (Agent Identity Management)"
PHRASE_RE = re.compile(r"OpenA2A\s+(AIM)\s+\(Agent\s+Identity\s+Management\)")
AIM_RE = re.compile(r"\bAIM\b")
BANNED = [
    ("ARIA", re.compile(r"(?<!WAI-)\bARIA\b")),
    ("trust layer", re.compile(r"\btrust\s+layer\b", re.IGNORECASE)),
]


def markdown_files(root):
    """Every *.md under root, skipping hidden directories, in a stable order."""
    found = []
    for path in sorted(root.rglob("*.md")):
        rel = path.relative_to(root)
        if any(part.startswith(".") for part in rel.parts[:-1]):
            continue
        if "node_modules" in rel.parts:
            continue
        found.append(path)
    return found


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def check_file(rel, text):
    failures = []

    first = AIM_RE.search(text)
    if first:
        expanded = {m.start(1) for m in PHRASE_RE.finditer(text)}
        if first.start() not in expanded:
            failures.append(
                f"{rel}:{line_of(text, first.start())} [first-use] the first AIM in "
                f'this file is bare; write "{PHRASE}" at its first use'
            )

    for name, pattern in BANNED:
        for m in pattern.finditer(text):
            failures.append(
                f"{rel}:{line_of(text, m.start())} [product-name] {name!r} is used as "
                f"a name; describe what the component does instead"
            )

    return failures


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
    using = 0
    for path in files:
        text = path.read_text(encoding="utf-8")
        if AIM_RE.search(text):
            using += 1
        failures.extend(check_file(path.relative_to(root).as_posix(), text))

    if failures:
        print("component names do not follow the naming rule:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print(
        f"naming ok: {len(files)} Markdown file(s) checked, {using} use AIM and "
        f"expand it at first use, none names ARIA or a trust layer"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
