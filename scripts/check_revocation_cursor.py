#!/usr/bin/env python3
"""Assert the specification text asks nothing of the revocation list it cannot carry.

ATP-SPEC v1.0.0-rc1 section 8.1 defines the revocation response as
{ "revocations": [...], "nextSince": "<RFC 3339>" } with additionalProperties
false at both levels. A conforming implementation has nowhere to carry a
version number for its revocation list; the cursor that advances when a
revocation is added is nextSince. Text in this repository that has a node
increment, publish or compare a CRL version therefore asks for something the
wire cannot express. Each entry in that response names the revoked agent by
agentDid and carries no agentId, so a verifier told to look an agentId up in
the list has no member to match it against.

Two rules, checked over every Markdown file in the tree (hidden directories
such as .git and a CI checkout of the conformance suite are skipped):

  crl-version   "CRL version" and "revocation list version" do not appear, in
                any case. The phrase may wrap across lines, since Markdown
                renders a soft line break as a space. Text that needs the
                revocation cursor names nextSince and cites ATP section 8.1.

  crl-key       No sentence names agentId and then the CRL or the revocation
                list, which is how a lookup of agentId in the list reads
                ("Check agentId against locally cached CRL"). The sentence may
                wrap across lines but not across a blank line. Text that looks
                an agent up in the list names agentDid.

CHANGELOG.md and errata/ are not checked: they record what earlier text said,
and an erratum quotes the published text verbatim by design.

Each failure is reported as file:line with its rule in brackets.

    python3 scripts/check_revocation_cursor.py [--root <tree>]

Exit 0 when every file passes, 1 otherwise.
"""

import argparse
import bisect
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

VERSION_RE = re.compile(r"\b(?:CRL|revocation[\s-]+list)\s+version\b", re.IGNORECASE)
# The crl-key rule: agentId, then the list later in the same sentence, with no
# sentence end (., ! or ? before whitespace or the end of the text) and no blank
# line between them. Each part is found once per file and key_offsets pairs
# them; one regex spanning the sentence scanned the rest of it again for every
# agentId in it.
AGENT_ID_RE = re.compile(r"\bagentId\b")
LIST_RE = re.compile(r"\b(?i:CRL|revocation[\s-]+list)\b")
SENTENCE_STOP_RE = re.compile(r"[.!?](?=\s|$)|\n(?=[ \t]*\n)")
NEWLINE_RE = re.compile(r"\n")
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


def newline_offsets(text):
    """Where each newline of text stands, found once per file."""
    return [m.start() for m in NEWLINE_RE.finditer(text)]


def line_of(newlines, offset):
    """The line offset sits on, found by bisecting the newline offsets.
    Counting newlines from the start of the file for each failure took time
    quadratic in the number of failures."""
    return bisect.bisect_left(newlines, offset) + 1


def key_offsets(text):
    """Where each crl-key match starts: an agentId whose first list after it
    comes before the next sentence stop. The next match is looked for from the
    end of that list, as re.finditer resumes after a match, so the agentIds, the
    lists and the stops are each walked once."""
    lists = [(m.start(), m.end()) for m in LIST_RE.finditer(text)]
    stops = [m.start() for m in SENTENCE_STOP_RE.finditer(text)]
    found = []
    next_list = next_stop = resume = 0
    for m in AGENT_ID_RE.finditer(text):
        if m.start() < resume:
            continue
        while next_list < len(lists) and lists[next_list][0] < m.end():
            next_list += 1
        if next_list == len(lists):
            break
        while next_stop < len(stops) and stops[next_stop] < m.end():
            next_stop += 1
        list_start, list_end = lists[next_list]
        if next_stop < len(stops) and stops[next_stop] < list_start:
            continue
        found.append(m.start())
        resume = list_end
    return found


def check_file(rel, text):
    newlines = newline_offsets(text)
    failures = [
        f"{rel}:{line_of(newlines, m.start())} [crl-version] {' '.join(m.group(0).split())!r} "
        f"cannot be carried by the ATP section 8.1 revocation response; name the "
        f"nextSince cursor instead"
        for m in VERSION_RE.finditer(text)
    ]
    failures.extend(
        f"{rel}:{line_of(newlines, offset)} [crl-key] agentId is looked up in the revocation "
        f"list, whose ATP section 8.1 entries carry agentDid and no agentId; name agentDid "
        f"instead"
        for offset in key_offsets(text)
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
        failures.extend(check_file(path.relative_to(root).as_posix(), path.read_text(encoding="utf-8")))

    if failures:
        print("revocation text asks for something the wire cannot carry:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print(
        f"revocation cursor ok: {len(files)} Markdown file(s) checked, none names a CRL version "
        f"or looks agentId up in the revocation list"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
