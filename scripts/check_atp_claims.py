#!/usr/bin/env python3
"""Assert the specification text claims nothing of ATP that ATP does not have.

ATP-SPEC v1.0.0-rc1 defines no version negotiation: the word does not occur in
it. A signature suite or any other registered value therefore changes only by
specification revision, and text that adds one "via ATP version negotiation"
names a mechanism a conforming implementation cannot run. No Internet-Draft for
ATP has been submitted to the IETF either (individual drafts exist for AIP and
AAP), and a working group draft is one a working group has adopted, so text
that calls ATP one states an adoption that has not happened.

Two rules, checked over every Markdown file in the tree (hidden directories
such as .git and a CI checkout of the conformance suite are skipped, and so is
node_modules):

  negotiation   No sentence names a negotiation (negotiate, negotiation and the
                other forms, in any case) together with ATP or the word
                version, in either order. The sentence may wrap across lines
                but not across a blank line. Text that needs the change policy
                says specification revision, as core.md section 14 does. When
                ATP defines a negotiation, this rule goes in the same change
                that cites the ATP section defining it.

  wg-draft      "Working Group draft", "working-group Internet-Draft" and "WG
                draft" do not appear, in any case. The phrase may wrap across
                lines. Text that describes the IETF work says what is intended:
                an individual Internet-Draft, then adoption by a working group.
                When a working group adopts ATP, this rule goes in the same
                change that names the adopted draft.

CHANGELOG.md and errata/ are not checked: they record what earlier text said,
and an erratum quotes the published text verbatim by design.

Each failure is reported as file:line with its rule in brackets.

    python3 scripts/check_atp_claims.py [--root <tree>]

Exit 0 when every file passes, 1 otherwise.
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# A sentence ends at ., ! or ? before whitespace or the end of the text, or at a
# blank line. Section numbers such as 1.3a.2 and versions such as v1.0.0 have no
# whitespace after their dots and do not end a sentence.
SENTENCE_END_RE = re.compile(r"[.!?](?=\s|$)|\n[ \t]*\r?\n")
NEGOTIATION_RE = re.compile(r"\bnegotiat\w*", re.IGNORECASE)
SUBJECT_RE = re.compile(r"\bATP\b|\b(?i:version)\b")
WG_DRAFT_RE = re.compile(
    r"\b(?:working[\s-]+group|WG)[\s-]+(?:Internet[\s-]+)?draft\b", re.IGNORECASE
)
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


def sentences(text):
    """(start, end) offsets of each sentence in text."""
    start = 0
    for m in SENTENCE_END_RE.finditer(text):
        yield start, m.end()
        start = m.end()
    yield start, len(text)


def check_file(rel, text):
    failures = []
    for start, end in sentences(text):
        m = NEGOTIATION_RE.search(text, start, end)
        if m and SUBJECT_RE.search(text, start, end):
            failures.append(
                f"{rel}:{line_of(text, m.start())} [negotiation] {m.group(0)!r} names a "
                f"negotiation that ATP-SPEC v1.0.0-rc1 does not define; state the change "
                f"policy, specification revision, instead"
            )
    failures.extend(
        f"{rel}:{line_of(text, m.start())} [wg-draft] {' '.join(m.group(0).split())!r} states "
        f"a working group adoption of ATP that has not happened; describe the IETF work "
        f"as intended instead"
        for m in WG_DRAFT_RE.finditer(text)
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
        print("the text claims something of ATP that ATP does not have:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print(
        f"ATP claims ok: {len(files)} Markdown file(s) checked, none names an ATP version "
        f"negotiation or calls ATP a working group draft"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
