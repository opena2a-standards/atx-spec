#!/usr/bin/env python3
"""Assert that the Markdown documents cite an A2A issue closed as a duplicate as one.

OpenA2A opened two coordination issues with the same title on a2aproject/A2A
for the AIP + ATP + ATX spec set: #1876 on 2026-05-24 and #1885 on 2026-05-28.
#1876 was closed on 2026-06-15 with a comment that closes it as a duplicate of
#1885 and says to continue on #1885; GitHub records that closure as not
planned. Text that cites #1876 without #1885 presents the duplicate closure as
the outcome of the coordination, as core.md section 2 did.

One rule, checked over every Markdown file in the tree (hidden directories
such as .git and a CI checkout of the conformance suite are skipped, and so is
node_modules):

  duplicate   A paragraph that cites an issue named in DUPLICATES also cites
              the issue it duplicates and says duplicate, duplicates or
              duplicated, in any case. DUPLICATES maps #1876 to #1885. A
              paragraph is the text between blank lines (a line of spaces and
              tabs is blank), so it may wrap across lines, and a list or a
              table with no blank line in it is one paragraph. When a
              document cites another A2A issue that was closed as a
              duplicate, its entry goes in DUPLICATES in the same change.

An issue is cited as #1876, A2A#1876, a2aproject/A2A#1876, or a URL path
github.com/a2aproject/A2A/issues/1876 or github.com/a2aproject/A2A/pull/1876;
the A2A prefix and the URL path may be in any case. A citation in one of the #
forms does not start right after a letter, a digit, _, /, # or &, so a URL
fragment such as page#1876, an HTML character reference such as &#1876; and
opena2a/A2A#1876 are not citations; nor is a number that runs on into a
letter, a digit or _, as in #18760. The check does not read what the paragraph
says the issue duplicates: a paragraph that cites both issues and says
duplicate of something else passes.

CHANGELOG.md and errata/ are not checked: they record what earlier text said,
and an erratum quotes the published text verbatim by design.

Each failure is reported as file:line with its rule in brackets, once per
paragraph, at the paragraph's first citation of the duplicate. A file that is
not UTF-8, or that cannot be read, is reported as a failure and not checked.

    python3 scripts/check_a2a_citations.py [--root <tree>]

Exit 0 when every file passes, 1 otherwise, and 2 on a usage error.
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Each a2aproject/A2A issue the documents may cite that was closed as a
# duplicate, mapped to the issue it duplicates.
DUPLICATES = {1876: 1885}

BLANK_LINE_RE = re.compile(r"\n[ \t]*\r?\n")
DUPLICATE_RE = re.compile(r"\bduplicate[sd]?\b", re.IGNORECASE)
HISTORY = {"CHANGELOG.md"}
HISTORY_DIRS = {"errata"}


def citation_re(number):
    """A citation of a2aproject/A2A issue `number`, in the forms the docstring lists."""
    return re.compile(
        r"(?:(?<![\w/#&])(?i:(?:a2aproject/)?A2A)?#"
        r"|(?i:github\.com/a2aproject/A2A/(?:issues|pull)/))"
        rf"{number}(?!\w)"
    )


CITATIONS = {n: citation_re(n) for pair in DUPLICATES.items() for n in pair}


def markdown_files(root):
    """Every *.md file under root, skipping hidden directories and history, in a stable order."""
    found = []
    for path in sorted(root.rglob("*.md")):
        rel = path.relative_to(root)
        if any(part.startswith(".") for part in rel.parts[:-1]):
            continue
        if "node_modules" in rel.parts:
            continue
        if rel.as_posix() in HISTORY or (len(rel.parts) > 1 and rel.parts[0] in HISTORY_DIRS):
            continue
        if path.is_file():
            found.append(path)
    return found


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def paragraphs(text):
    """(start, end) offsets of each paragraph: the text between blank lines."""
    start = 0
    for m in BLANK_LINE_RE.finditer(text):
        yield start, m.start()
        start = m.end()
    yield start, len(text)


def check_file(rel, text):
    """The failures of one file, and how many of its paragraphs cite a duplicate."""
    failures, cited = [], 0
    for start, end in paragraphs(text):
        for duplicate, original in DUPLICATES.items():
            m = CITATIONS[duplicate].search(text, start, end)
            if not m:
                continue
            cited += 1
            if CITATIONS[original].search(text, start, end) and DUPLICATE_RE.search(
                text, start, end
            ):
                continue
            failures.append(
                f"{rel}:{line_of(text, m.start())} [duplicate] {m.group(0)!r} cites "
                f"a2aproject/A2A#{duplicate}, which was closed as a duplicate of #{original}, "
                f"in a paragraph that does not both cite #{original} and say duplicate"
            )
    return failures, cited


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(ROOT), help="tree to check (default: this repository)")
    args = ap.parse_args()
    root = pathlib.Path(args.root).resolve()

    files = markdown_files(root)
    if not files:
        print(f"no Markdown files under {root}; refusing to pass vacuously", file=sys.stderr)
        return 1

    failures, cited = [], 0
    for path in files:
        rel = path.relative_to(root).as_posix()
        try:
            text = path.read_bytes().decode("utf-8")
        except UnicodeDecodeError as exc:
            failures.append(f"{rel} [encoding] not UTF-8 ({exc.reason}); cannot be checked")
            continue
        except OSError as exc:
            reason = exc.strerror or exc
            failures.append(f"{rel} [read] cannot read the file ({reason}); cannot be checked")
            continue
        found, n = check_file(rel, text)
        failures.extend(found)
        cited += n

    if failures:
        print("the A2A citations check failed:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    names = ", ".join(f"#{n}" for n in DUPLICATES)
    print(
        f"A2A citations ok: {len(files)} Markdown file(s) checked; {cited} paragraph(s) cite an "
        f"a2aproject/A2A issue closed as a duplicate ({names}), and each also cites the issue "
        f"it duplicates and says duplicate"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
