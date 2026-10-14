#!/usr/bin/env python3
"""Assert every restated expiry check names the validity window core.md section 1.3 step 2 defines.

core.md section 1.3 step 2 bounds an ATX by two signed timestamps: it is expired
at the earlier of expiresAt and issuedAt plus the seven-day credential TTL of
section 1.2, and it is not yet valid while issuedAt is in the future. A step
that checks expiresAt alone ("Check expiresAt is in the future") accepts a
credential whose expiresAt was set past that TTL and one issued in the future,
so it restates a weaker algorithm than section 1.3. The verifier's clock is
compared with both bounds, so the check is not a single comparison either.

Two rules, checked over every Markdown file in the tree:

  expiry-alone       A step that names expiresAt and a check verb also names
                     issuedAt. A step is a paragraph, a list item, a heading or
                     one table cell; it may wrap across lines but does not
                     cross a blank line, a heading, another list item or
                     another cell. The check verbs are check, verify, validate,
                     compare and reject in any form and in any case.
  single-comparison  A paragraph, list item, heading or table row that names
                     an expiry or validity window check (a word beginning with
                     "expir", or "validity window") does not call it a single
                     comparison or one comparison. A table row is read whole,
                     so a cost table's step cell and its notes cell are read
                     together. Letter case is ignored.

CHANGELOG.md and errata/ are not checked: they record what earlier text said,
and an erratum quotes the published text verbatim by design. Hidden
directories and node_modules are skipped. A file that is not UTF-8 fails rather
than being skipped.

Each failure is reported as file:line with its rule in brackets.

    python3 scripts/check_validity_window.py [--root <tree>]

Exit 0 when every file passes, 1 otherwise.
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

EXPIRES_RE = re.compile(r"\bexpiresAt\b")
ISSUED_RE = re.compile(r"\bissuedAt\b")
CHECK_RE = re.compile(
    r"\b(?:check(?:s|ed|ing)?|verif(?:y|ies|ied|ying)|validat(?:e|es|ed|ing)"
    r"|compar(?:e|es|ed|ing)|reject(?:s|ed|ing)?)\b",
    re.IGNORECASE,
)
EXPIRY_RE = re.compile(r"\bexpir\w*|\bvalidity\s+window\b", re.IGNORECASE)
SINGLE_RE = re.compile(r"\b(?:single|one)\s+comparison\b", re.IGNORECASE)
BLOCK_START_RE = re.compile(r"^\s*(?:#+\s|\d+\.\s|[-*+]\s|\|)")
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


def blocks(lines):
    """(first line number, text) per paragraph, list item, heading or table row.

    Continuation lines join their block with a newline, so a step may wrap
    across a soft line break and still report the line a word sits on.
    """
    out = []
    start, buf = None, []
    for number, line in enumerate(lines, 1):
        if not line.strip() or BLOCK_START_RE.match(line):
            if buf:
                out.append((start, "\n".join(buf)))
            start, buf = None, []
            if not line.strip():
                continue
            if line.lstrip().startswith(("|", "#")):
                out.append((number, line))
                continue
        if start is None:
            start = number
        buf.append(line)
    if buf:
        out.append((start, "\n".join(buf)))
    return out


def steps(block):
    """The block itself, or each cell of a table row."""
    return block.split("|") if block.lstrip().startswith("|") else [block]


def check_file(rel, text):
    failures = []
    for first, block in blocks(text.splitlines()):
        single = SINGLE_RE.search(block)
        if single and EXPIRY_RE.search(block):
            at = first + block.count("\n", 0, single.start())
            failures.append(
                f"{rel}:{at} [single-comparison] an expiry check called a single comparison; "
                f"core.md section 1.3 step 2 compares the verifier's clock with the earlier of "
                f"expiresAt and issuedAt plus the credential TTL, and with issuedAt"
            )
        for step in steps(block):
            expires = EXPIRES_RE.search(step)
            if expires is None or ISSUED_RE.search(step) or not CHECK_RE.search(step):
                continue
            at = first + step.count("\n", 0, expires.start())
            failures.append(
                f"{rel}:{at} [expiry-alone] a check of expiresAt that does not name issuedAt; "
                f"core.md section 1.3 step 2 expires an ATX at the earlier of expiresAt and "
                f"issuedAt plus the credential TTL, and rejects one whose issuedAt is in the future"
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
    for path in files:
        rel = path.relative_to(root).as_posix()
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError as exc:
            failures.append(f"{rel} [not-utf-8] {exc.reason}; cannot check it")
            continue
        failures.extend(check_file(rel, text))

    if failures:
        print("an expiry check disagrees with core.md section 1.3 step 2:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print(
        f"validity window ok: {len(files)} Markdown file(s) checked, every step that checks "
        f"expiresAt also names issuedAt, and no expiry check is called a single comparison"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
