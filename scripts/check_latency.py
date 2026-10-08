#!/usr/bin/env python3
"""Assert every stated verification latency total agrees with the cost model.

The cost of local verification is broken down step by step in scalability.md
section 2.1. Every other place that states a total states the same figure, so a
reader who meets two of them never has to choose:

  warm   under 5 ms. A warm cache holds the issuer's DID document and the
         revocation list; the total includes the ML-DSA-65 verification that
         the family signature gate requires of a hybrid credential.
  cold   under 50 ms. A cold cache adds one DID document fetch.

A statement is a sentence (or a table row) in which a bound appears: "under",
"sub" or "below" followed by a number and "ms" or "millisecond(s)", or a range
"N to M ms". A bound belongs to the nearest kind named before it in the same
sentence, else to the first one named after it: "warm cache" or "local
verification" is warm, "cold cache" or "cold start" is cold. In a table row
whose first cell names a kind, or is exactly "Verification", a bound with no
kind in its own sentence takes the row's kind. A bound that belongs to no kind
is a per-step figure.

Rules, each failure reported as file:line with its rule in brackets:

  latency   an "under" bound for a kind states that kind's figure, and a range
            for a kind does not end above it.
  step      in a numbered list that states a warm cache total, a per-step bound
            stays below that total: the steps add up to it, so no one step
            can take all of it.
  missing   core.md states both totals and README.md states the warm one, so
            rewording them away cannot pass vacuously.

Every Markdown file in the tree is checked except CHANGELOG.md and errata/,
which record what earlier text said. Hidden directories and node_modules are
skipped. A file that is not UTF-8 fails rather than being skipped.

    python3 scripts/check_latency.py [--root <tree>]

Exit 0 when every statement agrees, 1 otherwise.
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

FIGURES_MS = {"warm": 5, "cold": 50}
REQUIRED = [("core.md", "warm"), ("core.md", "cold"), ("README.md", "warm")]
HISTORY = {"CHANGELOG.md"}
HISTORY_DIRS = {"errata"}

KIND_RE = re.compile(
    r"\b(?P<warm>warm\s+cache|local\s+verification)\b|\b(?P<cold>cold\s+(?:cache|start))\b",
    re.IGNORECASE,
)
UNIT = r"\s*(?:ms|milliseconds?)\b"
BOUND_RE = re.compile(
    r"\b(?:under|sub|below)\s+(?P<bound>\d+(?:\.\d+)?)" + UNIT
    + r"|\b(?P<low>\d+(?:\.\d+)?)\s+to\s+(?P<high>\d+(?:\.\d+)?)" + UNIT,
    re.IGNORECASE,
)
SENTENCE_END_RE = re.compile(r"(?<=[.!?])\s+")
BLOCK_START_RE = re.compile(r"^\s*(?:#+\s|\d+\.\s|[-*+]\s|\|)")
LIST_ITEM_RE = re.compile(r"^\s*\d+\.\s")


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

    Continuation lines join their block with a newline, so a phrase may wrap
    across a soft line break and still report the line it sits on.
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


def sentences(text):
    """(offset, sentence) pairs."""
    pos = 0
    for m in SENTENCE_END_RE.finditer(text):
        yield pos, text[pos:m.start()]
        pos = m.end()
    if pos < len(text):
        yield pos, text[pos:]


def kind_of(match):
    return "warm" if match.group("warm") else "cold"


def row_kind(text):
    """The kind a table row's first cell names, if any."""
    if not text.lstrip().startswith("|"):
        return None
    cells = text.strip().strip("|").split("|")
    first = cells[0].strip()
    if first.lower() == "verification":
        return "warm"
    named = KIND_RE.search(first)
    return kind_of(named) if named else None


def statements(text):
    """(offset, kind, match) for every bound in a block, in offset order.

    kind is None for a per-step bound. Kinds and bounds are both found in
    sentence order, so one pass over each places every bound.
    """
    row = row_kind(text)
    parts = text.split("|") if row is not None else [text]
    offset = 0
    for part in parts:
        for start, sentence in sentences(part):
            kinds = [(m.start(), kind_of(m)) for m in KIND_RE.finditer(sentence)]
            passed = 0
            for bound in BOUND_RE.finditer(sentence):
                while passed < len(kinds) and kinds[passed][0] < bound.start():
                    passed += 1
                if passed:
                    kind = kinds[passed - 1][1]
                elif kinds:
                    kind = kinds[0][1]
                else:
                    kind = row
                yield offset + start + bound.start(), kind, bound
        offset += len(part) + 1


def upper_ms(bound):
    """The largest figure a bound allows: its "under" number or the end of its range."""
    return float(bound.group("bound") if bound.group("bound") is not None else bound.group("high"))


def step_failures(rel, numbered):
    """[step] failures for one numbered list, given (line, kind, match) per bound in it."""
    if not any(kind == "warm" for _, kind, _ in numbered):
        return []
    figure = FIGURES_MS["warm"]
    return [
        f"{rel}:{line} [step] {' '.join(bound.group(0).split())!r} for one step of a list "
        f"whose warm cache total is under {figure} ms; the steps add up to the total, "
        f"so each one is below it"
        for line, kind, bound in numbered
        if kind is None and upper_ms(bound) >= figure
    ]


def check_file(rel, text, seen):
    failures = []
    numbered = []  # (line, kind, match) per bound in the numbered list being read
    for first, block in blocks(text.splitlines()) + [(None, "")]:
        in_list = bool(LIST_ITEM_RE.match(block))
        if not in_list:
            failures.extend(step_failures(rel, numbered))
            numbered = []
        line, counted = first, 0
        for offset, kind, bound in statements(block):
            # Offsets only grow, so each newline is counted once per block.
            line += block.count("\n", counted, offset)
            counted = offset
            if in_list:
                numbered.append((line, kind, bound))
            if kind is None:
                continue
            seen.add((rel, kind))
            figure = FIGURES_MS[kind]
            stated = " ".join(bound.group(0).split())
            if bound.group("bound") is not None:
                wrong = float(bound.group("bound")) != figure
            else:
                wrong = float(bound.group("high")) > figure
            if wrong:
                failures.append(
                    f"{rel}:{line} [latency] {stated!r} for the {kind} cache total; "
                    f"every surface states under {figure} ms (scalability.md section 2.1)"
                )
    return failures


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(ROOT), help="tree to check (default: this repository)")
    args = ap.parse_args()
    root = pathlib.Path(args.root).resolve()

    failures = []
    seen = set()
    for path in markdown_files(root):
        rel = path.relative_to(root).as_posix()
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError as exc:
            failures.append(f"{rel} [latency] not UTF-8 ({exc.reason}); cannot check it")
            continue
        failures.extend(check_file(rel, text, seen))
    for rel, kind in REQUIRED:
        if (rel, kind) not in seen:
            failures.append(
                f"{rel} [missing] states no {kind} cache verification total; "
                f"it should say under {FIGURES_MS[kind]} ms"
            )

    if failures:
        print("verification latency totals disagree:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print(f"latency ok: {len(seen)} file and kind pair(s) state the verification totals")
    return 0


if __name__ == "__main__":
    sys.exit(main())
