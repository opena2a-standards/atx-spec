#!/usr/bin/env python3
"""Assert how the Markdown documents in this repository name OpenA2A components.

Two rules, checked over every Markdown file in the tree (hidden directories such
as .git and a CI checkout of the conformance suite are skipped, and so is
node_modules):

  first-use     The first occurrence of the whole word AIM in a file is the AIM
                in "OpenA2A AIM (Agent Identity Management)". A bare AIM ahead
                of it, including a link in the navigation bar, fails. An IETF
                working group document defines "Agent Identity Management
                System (AIMS)", so a reader who meets a bare AIM first cannot
                tell the two apart. AIMS is a different word and does not count.
                The expansion counts only where a reader sees it: the phrase
                inside an HTML comment or a link title does not count, while
                an AIM there still counts as a use.

  product-name  ARIA does not appear as a name, and the phrase "trust layer"
                does not appear at all, not even as a description: it is an
                internal component name, so a descriptive use reads as that
                name. Text that needs the component says what it does instead
                (threat research, for example). WAI-ARIA, the W3C
                accessibility specification, is not this name and is allowed.

The phrase may wrap across one line break, since Markdown renders a soft line
break as a space; a blank line between its words is a paragraph break and does
not count. Each failure is reported as file:line with its rule in brackets, at
most MAX_REPORTED per file followed by a count of the rest. A file that is not
UTF-8 text is reported as an [encoding] failure.

    python3 scripts/check_naming.py [--root <tree>]

Exit 0 when every file passes, 1 when a file fails or cannot be read, and 2 on
a usage error such as an unknown option.
"""

import argparse
import bisect
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

MAX_REPORTED = 20

# Whitespace between two words of a phrase: spaces and tabs with at most one
# line break, which Markdown renders as a space. Two line breaks end a paragraph.
GAP = r"(?=\s)[ \t]*(?:\r?\n)?[ \t]*"

PHRASE = "OpenA2A AIM (Agent Identity Management)"
PHRASE_RE = re.compile(
    rf"OpenA2A{GAP}(AIM){GAP}\(Agent{GAP}Identity{GAP}Management\)"
)
AIM_RE = re.compile(r"\bAIM\b")
BANNED = [
    (
        re.compile(r"(?<!WAI-)\bARIA\b"),
        "'ARIA' is used as a name; describe what the component does instead",
    ),
    (
        re.compile(rf"\btrust{GAP}layer\b", re.IGNORECASE),
        "'trust layer' is an internal component name and is not used, even as a "
        "description; say what the text means instead",
    ),
]

# Text a reader does not see on the rendered page.
HTML_COMMENT_RE = re.compile(r"<!--.*?(?:-->|\Z)", re.DOTALL)
# A title may wrap onto the next line but never spans a blank line.
_LINE = r"\n(?![ \t]*\r?\n)"
TITLE = (
    rf'("(?:[^"\\\n]|\\.|{_LINE})*"'
    rf"|'(?:[^'\\\n]|\\.|{_LINE})*'"
    rf"|\((?:[^()\\\n]|\\.|{_LINE})*\))"
)
INLINE_TITLE_RE = re.compile(
    r"\]\(\s*(?:<[^<>\n]*>|[^\s()<>]*(?:\([^\s()]*\)[^\s()<>]*)*)\s+" + TITLE + r"\s*\)",
    re.DOTALL,
)
REFERENCE_TITLE_RE = re.compile(
    r"^ {0,3}\[[^\]\n]+\]:[ \t]*(?:<[^<>\n]*>|\S+)(?:[ \t]+|[ \t]*\r?\n[ \t]*)"
    + TITLE
    + r"[ \t]*$",
    re.MULTILINE | re.DOTALL,
)


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


def hidden_spans(text):
    """Sorted, merged (start, end) offsets of HTML comments and link titles."""
    spans = [m.span() for m in HTML_COMMENT_RE.finditer(text)]
    for pattern in (INLINE_TITLE_RE, REFERENCE_TITLE_RE):
        spans.extend(m.span(1) for m in pattern.finditer(text))
    merged = []
    for start, end in sorted(spans):
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged


def overlaps(spans, start, end):
    """True when [start, end) intersects any span in the sorted, merged list."""
    i = bisect.bisect_right(spans, (start, float("inf"))) - 1
    if i >= 0 and spans[i][1] > start:
        return True
    return i + 1 < len(spans) and spans[i + 1][0] < end


class Lines:
    """Line numbers by offset, from newline positions found once per file."""

    def __init__(self, text):
        self.newlines = [m.start() for m in re.finditer("\n", text)]

    def of(self, offset):
        return bisect.bisect_left(self.newlines, offset) + 1


def check_file(text):
    """Failures for one file, as (offset, message) pairs in report order."""
    failures = []

    first = AIM_RE.search(text)
    if first:
        hidden = hidden_spans(text)
        expanded = {
            m.start(1) for m in PHRASE_RE.finditer(text) if not overlaps(hidden, *m.span())
        }
        if first.start() not in expanded:
            failures.append(
                (
                    first.start(),
                    "[first-use] the first AIM in this file is bare; write "
                    f'"{PHRASE}" at its first use, outside an HTML comment or a '
                    "link title",
                )
            )

    for pattern, message in BANNED:
        for m in pattern.finditer(text):
            failures.append((m.start(), f"[product-name] {message}"))

    return failures


def report_file(rel, text):
    """Report lines for one file, capped at MAX_REPORTED plus a count of the rest."""
    failures = check_file(text)
    if not failures:
        return []
    lines = Lines(text)
    shown = [f"{rel}:{lines.of(offset)} {message}" for offset, message in failures[:MAX_REPORTED]]
    rest = len(failures) - len(shown)
    if rest:
        shown.append(f"{rel}: {rest} more failure(s) in this file not shown")
    return shown


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
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
        rel = path.relative_to(root).as_posix()
        try:
            data = path.read_bytes()
        except OSError as e:
            failures.append(f"{rel}:1 [unreadable] {e.strerror or e}")
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError as e:
            line = data.count(b"\n", 0, e.start) + 1
            failures.append(
                f"{rel}:{line} [encoding] byte {data[e.start]:#04x} at offset {e.start} "
                "is not UTF-8; save the file as UTF-8"
            )
            continue
        if AIM_RE.search(text):
            using += 1
        failures.extend(report_file(rel, text))

    if failures:
        print("component names do not follow the naming rule:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print(
        f"naming ok: {len(files)} Markdown file(s) checked, {using} use AIM and "
        f"expand it at first use, none names ARIA or uses the phrase trust layer"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
