#!/usr/bin/env python3
"""Assert the README opens with its title and a one-sentence description only.

A reader decides from the README's first screen whether to open the
specification, so what stands between the title and the first section heading
is the one sentence that says what the repository covers. Anything longer
belongs under a section or on a page under docs/ that the README links; the
summary that used to sit there is in docs/use-cases.md.

Two rules, checked on README.md at the top of the tree:

  lead      Between the "# " title and the first "## " heading there is one
            paragraph, and it is one sentence. Lines made only of badge images
            and lines that are only an HTML comment do not count. Lines above
            the title, such as the navigation line, are not checked. A second
            paragraph is reported at its first line, a second sentence at the
            line it starts on.
  missing   README.md exists and has a "# " title, a "## " heading after it
            and a description between them, so removing any of them cannot
            pass vacuously.

A heading inside a fenced code block is not a heading. A sentence ends at ".",
"!" or "?" followed by white space and a capital letter, a digit or the start
of Markdown markup. A file that is not UTF-8 is reported as an [encoding]
failure.

    python3 scripts/check_readme_lead.py [--root <tree>]

Exit 0 when the README passes, 1 when it fails or cannot be read, and 2 on a
usage error such as an unknown option.
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
README = "README.md"

FENCE_RE = re.compile(r"^\s*(```|~~~)")
H1_RE = re.compile(r"^#\s")
H2_RE = re.compile(r"^##\s")
IMAGE = r"!\[[^\]]*\]\([^)]*\)"
BADGE_LINE_RE = re.compile(r"^(?:\s*(?:\[" + IMAGE + r"\]\([^)]*\)|" + IMAGE + r"))+\s*$")
COMMENT_LINE_RE = re.compile(r"^\s*<!--.*-->\s*$")
SENTENCE_END_RE = re.compile(r"[.!?](?=\s+[A-Z0-9*_`\[(])")


def headings(lines):
    """(line number of the title, line number of the first section heading after it)."""
    title = section = None
    fenced = False
    for number, line in enumerate(lines, 1):
        if FENCE_RE.match(line):
            fenced = not fenced
            continue
        if fenced:
            continue
        if title is None and H1_RE.match(line):
            title = number
        elif title is not None and H2_RE.match(line):
            section = number
            break
    return title, section


def paragraphs(lines, first, last):
    """[(first line number, [(line number, text), ...])] for lines first..last."""
    out, current = [], []
    for number in range(first, last + 1):
        line = lines[number - 1]
        if not line.strip() or BADGE_LINE_RE.match(line) or COMMENT_LINE_RE.match(line):
            if current:
                out.append((current[0][0], current))
            current = []
            continue
        current.append((number, line))
    if current:
        out.append((current[0][0], current))
    return out


def second_sentence_line(paragraph):
    """Line number on which the paragraph's second sentence starts, or None."""
    text, starts = "", []
    for number, line in paragraph:
        starts.append((len(text), number))
        text += line.strip() + " "
    end = SENTENCE_END_RE.search(text.rstrip())
    if end is None:
        return None
    offset = end.end() + 1
    found = starts[0][1]
    for start, number in starts:
        if start <= offset:
            found = number
    return found


def check(lines):
    """Failures as 'README.md:<line> [rule] message', and a summary for a pass."""
    title, section = headings(lines)
    if title is None:
        return [f"{README}:1 [missing] no '# ' title outside a code block"], None
    if section is None:
        return [f"{README}:{title} [missing] no '## ' section heading after the title"], None

    found = paragraphs(lines, title + 1, section - 1)
    if not found:
        return [f"{README}:{title} [missing] no description between the title and line {section}"], None

    failures = []
    first_line, first = found[0]
    second = second_sentence_line(first)
    if second is not None:
        failures.append(
            f"{README}:{second} [lead] the description above the first section heading "
            "is more than one sentence; keep one and move the rest under a section or to docs/"
        )
    for start, _ in found[1:]:
        failures.append(
            f"{README}:{start} [lead] a second paragraph above the first section heading "
            f"(line {section}); move it under a section or to docs/"
        )
    return failures, (title, first_line, section)


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--root", default=str(ROOT), help="tree to check (default: this repository)")
    args = ap.parse_args()
    path = pathlib.Path(args.root).resolve() / README

    try:
        data = path.read_bytes()
    except OSError as e:
        print(f"  - {README}:1 [missing] {e.strerror or e}", file=sys.stderr)
        return 1
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as e:
        line = data.count(b"\n", 0, e.start) + 1
        print(
            f"  - {README}:{line} [encoding] byte {data[e.start]:#04x} at offset {e.start} "
            "is not UTF-8; save the file as UTF-8",
            file=sys.stderr,
        )
        return 1

    failures, where = check(text.splitlines())
    if failures:
        print("the README does not open with a title and a one-sentence description:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    title, description, section = where
    print(
        f"readme lead ok: title on line {title}, a one-sentence description on line "
        f"{description}, first section heading on line {section}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
