#!/usr/bin/env python3
"""Assert the specification text describes the revocation list ATP-SPEC v1.0.0-rc1 section 8.1 defines.

ATP-SPEC v1.0.0-rc1 section 8.1 defines the revocation response as
{ "revocations": [...], "nextSince": "<RFC 3339>" }, and its schema
(https://specs.opena2a.org/schemas/atp/revocation-list-v1.schema.json) sets
additionalProperties false at both levels. The body has no member for a
signature, and core.md section 2 item 5 states that it is not signed in ATP 1.0
and places a signed revocation list in ATP 1.1. Each entry carries five required
members: agentDid, revokedAt, reason, transparencyLogIndex and revokedByKeyId.
EXAMPLE_ENTRY below is the section 8.1 example entry of ATP-SPEC v1.0.0-rc1, the
revision core.md and scalability.md cite; ENTRY_BYTES is its length as compact
JSON. Other revisions size the entry differently (the 1.1.0 draft's example
entry is 212 bytes, with a registered reason code and four required members),
so every message names the revision the figure comes from (SOURCE).

Three rules, checked over every Markdown file in the tree (hidden directories
such as .git and a CI checkout of the conformance suite are skipped):

  signed-crl    A sentence that names a CRL or a revocation does not say that a
                list, a response, a body or a cache is signed. A sentence that
                names ATP 1.1 passes, since that is where a signed list is
                placed, and so does a file signed for transport ("publish its
                CRL as a signed file"), which says nothing about the list.
  entry-size    In a paragraph that names a CRL or a revocation, a sentence that
                names an entry states no byte figure below ENTRY_BYTES.
  total-size    A size stated for a number of revocations is not below that
                number times ENTRY_BYTES. Units are decimal: 1 MB is 10^6 bytes.

scalability.md must state an entry size and a total size, so rewording them
away fails rather than passing vacuously.

A paragraph ends at a blank line, and each heading, table row and list item is
a paragraph of its own. A sentence ends at '.', '!' or '?' followed by white
space, and may wrap across lines, since Markdown renders a soft line break as a
space. Emphasis and code markers ('*' and '`') are ignored.

CHANGELOG.md and errata/ are not checked: they record what earlier text said,
and an erratum quotes the published text verbatim by design. A file that is not
UTF-8 fails rather than being skipped.

Each failure is reported as file:line with its rule in brackets.

    python3 scripts/check_revocation_list.py [--root <tree>]

Exit 0 when every file passes, 1 otherwise.
"""

import argparse
import bisect
import json
import pathlib
import re
import sys
from decimal import Decimal

ROOT = pathlib.Path(__file__).resolve().parent.parent

SOURCE = "ATP-SPEC v1.0.0-rc1 section 8.1"
# Copied by hand from SOURCE; change both together.
EXAMPLE_ENTRY = {
    "agentDid": "did:opena2a:mcp_server:compromised-package",
    "revokedAt": "2026-03-22T15:00:00Z",
    "reason": "Supply chain compromise detected",
    "transparencyLogIndex": 1847300,
    "revokedByKeyId": "did:opena2a:authority:opena2a.org#key-v3",
}
ENTRY_BYTES = len(json.dumps(EXAMPLE_ENTRY, separators=(",", ":")).encode("utf-8"))

HISTORY = {"CHANGELOG.md"}
HISTORY_DIRS = {"errata"}
REQUIRED = [("scalability.md", "entry"), ("scalability.md", "total")]

REVOCATION_RE = re.compile(r"\bCRLs?\b|\brevocations?\b", re.IGNORECASE)
SIGNED_RE = re.compile(
    r"\b(?:CRLs?|lists?|responses?|bod(?:y|ies)|caches?)\s+(?:is|are)\s+(?:\w+ly\s+)?signed\b",
    re.IGNORECASE,
)
LATER_REVISION_RE = re.compile(r"\bATP\s+1\.1\b")
ENTRY_RE = re.compile(r"\bentry\b|\bentries\b", re.IGNORECASE)
# A number starts only where a run of digits and commas starts. Without the
# lookbehind every position inside a long run is tried as a start and each try
# scans to the end of the run, which takes time quadratic in its length.
BYTES_RE = re.compile(r"(?<![\d,])(?P<n>\d[\d,]*)\s*bytes\b", re.IGNORECASE)
SCALES = {"thousand": 10**3, "million": 10**6, "billion": 10**9}
COUNT_RE = re.compile(
    r"(?:(?<![\w,])(?P<num>\d[\d,]*(?:\.\d+)?)\s+(?:(?P<scale>thousand|million|billion)\s+)?"
    r"|\b(?:one|a)\s+(?P<wscale>thousand|million|billion)\s+)revocations\b",
    re.IGNORECASE,
)
UNITS = {"bytes": 1, "kb": 10**3, "mb": 10**6, "gb": 10**9, "tb": 10**12}
SIZE_RE = re.compile(
    r"(?<![\d,])(?P<n>\d[\d,]*(?:\.\d+)?)\s*(?P<unit>bytes|KB|MB|GB|TB)\b", re.IGNORECASE
)
NEWLINE_RE = re.compile(r"\n")
BLOCK_START_RE = re.compile(r"[ \t]*(?:\||#|[-*+][ \t]|\d+[.)][ \t]|```|~~~)")
SENTENCE_END_RE = re.compile(r"(?<=[.!?])\s+")
MARKERS = str.maketrans("*`", "  ")


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


def newline_offsets(text):
    """Where each newline of text stands, found once per file."""
    return [m.start() for m in NEWLINE_RE.finditer(text)]


def line_of(newlines, offset):
    """The line offset sits on, found by bisecting the newline offsets.
    Counting newlines from the start of the file for each failure took time
    quadratic in the number of failures."""
    return bisect.bisect_left(newlines, offset) + 1


def paragraphs(text):
    """Yield (offset, paragraph) for each paragraph, heading, table row and list item."""
    start = None
    pos = 0
    for line in text.splitlines(keepends=True):
        if not line.strip():
            if start is not None:
                yield start, text[start:pos]
                start = None
        elif start is None:
            start = pos
        elif BLOCK_START_RE.match(line):
            yield start, text[start:pos]
            start = pos
        pos += len(line)
    if start is not None:
        yield start, text[start:]


def sentences(paragraph):
    """Yield (offset within the paragraph, sentence) for each sentence."""
    start = 0
    for m in SENTENCE_END_RE.finditer(paragraph):
        yield start, paragraph[start:m.start()]
        start = m.end()
    if paragraph[start:].strip():
        yield start, paragraph[start:]


def number(raw):
    return Decimal(raw.replace(",", ""))


def check_file(rel, text, seen):
    failures = []
    text = text.translate(MARKERS)
    newlines = newline_offsets(text)
    for p_off, para in paragraphs(text):
        names_revocations = bool(REVOCATION_RE.search(para))
        for s_off, sentence in sentences(para):
            base = p_off + s_off
            phrase = " ".join(sentence.split())

            if REVOCATION_RE.search(sentence) and not LATER_REVISION_RE.search(sentence):
                for m in SIGNED_RE.finditer(sentence):
                    failures.append(
                        f"{rel}:{line_of(newlines, base + m.start())} [signed-crl] "
                        f"{' '.join(m.group(0).split())!r}: the {SOURCE} revocation response "
                        f"is not signed in ATP 1.0 and has no member for a signature; a signed "
                        f"revocation list is ATP 1.1 work (core.md section 2 item 5)"
                    )

            if names_revocations and ENTRY_RE.search(sentence):
                for m in BYTES_RE.finditer(sentence):
                    seen.add((rel, "entry"))
                    if number(m.group("n")) < ENTRY_BYTES:
                        failures.append(
                            f"{rel}:{line_of(newlines, base + m.start())} [entry-size] "
                            f"{' '.join(m.group(0).split())!r} for a revocation entry in {phrase[:80]!r}; "
                            f"the {SOURCE} example entry is {ENTRY_BYTES} bytes as compact JSON"
                        )

            # Every size in the sentence, found once; each count takes the
            # first size after it. Searching the rest of the sentence once per
            # count would take time quadratic in the number of counts.
            sizes = list(SIZE_RE.finditer(sentence))
            size_starts = [m.start() for m in sizes]
            for count in COUNT_RE.finditer(sentence):
                after = bisect.bisect_left(size_starts, count.end())
                if after == len(sizes):
                    continue
                size = sizes[after]
                seen.add((rel, "total"))
                if count.group("num") is not None:
                    n = number(count.group("num")) * SCALES.get((count.group("scale") or "").lower(), 1)
                else:
                    n = Decimal(SCALES[count.group("wscale").lower()])
                stated = number(size.group("n")) * UNITS[size.group("unit").lower()]
                if stated < n * ENTRY_BYTES:
                    failures.append(
                        f"{rel}:{line_of(newlines, base + size.start())} [total-size] "
                        f"{' '.join(count.group(0).split())} stated as "
                        f"{' '.join(size.group(0).split())!r}; at {ENTRY_BYTES} bytes per {SOURCE} "
                        f"entry that many revocations take at least {n * ENTRY_BYTES:,.0f} bytes"
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
    seen = set()
    for path in files:
        rel = path.relative_to(root).as_posix()
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError as exc:
            failures.append(f"{rel} [revocation-list] not UTF-8 ({exc.reason}); cannot check it")
            continue
        failures.extend(check_file(rel, text, seen))
    for rel, kind in REQUIRED:
        if (rel, kind) not in seen:
            failures.append(
                f"{rel} [missing] states no revocation {kind} size; it should state one at "
                f"{ENTRY_BYTES} bytes per {SOURCE} entry"
            )

    if failures:
        print(f"revocation list text disagrees with {SOURCE}:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print(
        f"revocation list ok: {len(files)} Markdown file(s) checked, none calls the list signed "
        f"or sizes an entry below {ENTRY_BYTES} bytes, the {SOURCE} example entry"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
