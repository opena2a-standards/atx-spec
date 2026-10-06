#!/usr/bin/env python3
"""Assert that sections describing a format specified elsewhere name where it is.

A reader who follows a link to a section reads that section, not the document
header. So a section that describes a format this repository does not define
carries its own reference to the specification that does. Each entry in
POINTERS names a document, the line that opens the section (a heading or a
numbered list item), and the references the section has to contain.

A heading's section runs to the next heading at the same or a higher level; a
list item runs to the next blank line or the next numbered item. References may
wrap across lines, since Markdown renders a soft line break as a space. Each
failure is reported as file:line with its rule in brackets.

    python3 scripts/check_pointers.py [--root <tree>]

Exit 0 when every section carries its references, 1 otherwise. A document or
opening line that is missing also fails, so a renamed section cannot pass
vacuously.
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

ATP_REVOCATION = "ATP-SPEC v1.0.0-rc1 §8.1"
REVOCATION_SCHEMA = "https://specs.opena2a.org/schemas/atp/revocation-list-v1.schema.json"

POINTERS = [
    ("core.md", "5. **The revocation list format.**", (ATP_REVOCATION, REVOCATION_SCHEMA)),
    ("core.md", "### 3.3 Revocation flow", (ATP_REVOCATION, REVOCATION_SCHEMA)),
]

HEADING_RE = re.compile(r"^(#+)\s")
ITEM_RE = re.compile(r"^\d+\.\s")


def section(lines, start):
    """The lines of the section opened by lines[start]."""
    heading = HEADING_RE.match(lines[start])
    end = start + 1
    while end < len(lines):
        line = lines[end]
        if heading:
            other = HEADING_RE.match(line)
            if other and len(other.group(1)) <= len(heading.group(1)):
                break
        elif not line.strip() or ITEM_RE.match(line):
            break
        end += 1
    return lines[start:end]


def check(root):
    failures = []
    for rel, opening, references in POINTERS:
        path = root / rel
        if not path.is_file():
            failures.append(f"{rel} [pointer] file not found; it should hold {opening!r}")
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        start = next((i for i, line in enumerate(lines) if line.startswith(opening)), None)
        if start is None:
            failures.append(f"{rel} [pointer] no line opens with {opening!r}")
            continue
        body = " ".join(" ".join(section(lines, start)).split())
        for ref in references:
            if ref not in body:
                failures.append(
                    f"{rel}:{start + 1} [pointer] the section opened by {opening!r} does not "
                    f"cite {ref!r}; name where the format is specified in the section itself"
                )
    return failures


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(ROOT), help="tree to check (default: this repository)")
    args = ap.parse_args()
    root = pathlib.Path(args.root).resolve()

    failures = check(root)
    if failures:
        print("sections do not name where their format is specified:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print(f"pointers ok: {len(POINTERS)} section(s) name where their format is specified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
