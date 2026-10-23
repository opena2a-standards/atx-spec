#!/usr/bin/env python3
"""Assert that sections describing something specified elsewhere name where it is.

A reader who follows a link to a section reads that section, not the document
header. So a section that describes a format or a decision this repository does
not define carries its own reference to the specification that does. Each entry
in POINTERS names a document, the line that opens the section (a heading or a
list item), and the references the section has to contain.

The revocation list format is specified in ATP. Whether an agent may touch a
resource is decided under AAP, so every section that says where that decision
is made names AAP, and README.md and core.md name the same layer. Such a section
also calls nothing permitted in a sentence that does not name AAP, so it cannot
give the decision to a credential's capabilities a sentence later.

How many checks HackMyAgent ships and how many factors the AIP trust score
weighs are figures the HackMyAgent README and AIP §6.1 own. The rows of the
core.md product integration map that describe those projects link to those
sources and state no count of their own ([figure]): a numeral that is not part
of a section number, followed within three words by checks, factors, payloads,
rules or tests. A count restated here
drifts when the project ships; 209 static checks and an 8 factor trust score
stood in the map while the sources said 317 and 9.

Whether a credential carries enough signatures from a threshold key set is
checked by the verifier in core.md section 1.3 step 5. Four sections that
describe threshold signing name that step: core.md section 3.1 step 8 and
section 4.2 item 4, and sovereign-federation.md's section 2.2 HSM item and
section 2.3 threshold paragraph. So does docs/conformance.md's description of
the conformance suite's threshold fixture: that fixture carries every signature
of its key set, so it pins that each one verifies and not the threshold, and a
"2 of 3" with no pointer reads as a threshold someone checks. Other mentions of
threshold signing, such as the core.md section 1.2 lifecycle table, are not
checked.

The member keys and the threshold that step reads are the ones the authority's
DID document declares, in the thresholdKeySets member that core.md section
1.3b defines. The section 1.3 step 5 threshold bullet and sovereign-federation.md's
section 2.3 threshold paragraph each say that the DID document declares them,
and each names section 1.3b. Section 1.3b in turn names thresholdKeySets and
the two members of each set object, members and threshold ([definition]), so a
pointer to it cannot name a section that does not define the declaration.

The Coverage paragraph of core.md section 12 lists the requirements that no
conformance fixture exercises and says what the suite's threshold fixtures pin.
It names threshold-1of3-cosignature, the fixture that pins the rejection of a
credential carrying fewer signatures than the threshold of section 1.3 step 5
requires. Without that name the paragraph listed that threshold among the
requirements no fixture exercises and said that a verifier that never counts
signatures against it passes the threshold cosignature fixture.

A heading's section runs to the next heading at the same or a higher level; a
list item runs to the next blank line or the next list item, numbered or not; a
table row is one line. References may wrap across lines, since Markdown renders
a soft line break as a space. Each failure is reported as file:line with its
rule in brackets.

The forge lab at specs.opena2a.org/lab/forge signs a simplified object of its
own, not the JCS(TBS) of core.md §1.3a.2, and that object does not validate
against the credential schema. Until the lab verifies a real credential, every
sentence that names the lab, in a Markdown file outside CHANGELOG.md and
errata/, says that what it signs is not an ATX credential, so a reader does not
take its verdicts for conformance results. The sentence says the lab signs
something, with "the lab", "the forge lab", a Markdown link to the lab or "it"
directly before "signs" or "signed", before it says "not an ATX credential".
Those words describing anything else ("rejects anything that is not an ATX
credential") are not the caveat, and neither is a form of "sign" with another
subject ("checks what you signed") or used as a noun ("a sign of progress").

    python3 scripts/check_pointers.py [--root <tree>]

Exit 0 when every section carries its references, every section in DEFINITIONS
names what it defines and every sentence naming the forge lab carries its
caveat, 1 otherwise. A document or opening line that is missing also fails, so
a renamed section cannot pass vacuously.
"""

import argparse
import bisect
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

ATP_REVOCATION = "ATP-SPEC v1.0.0-rc1 §8.1"
REVOCATION_SCHEMA = "https://specs.opena2a.org/schemas/atp/revocation-list-v1.schema.json"
AUTHORIZATION = "AAP"
HMA_README = "https://github.com/opena2a-org/hackmyagent/blob/main/README.md"
AIP_TRUST = "AIP §6.1"
AIP_SPEC = "https://github.com/opena2a-standards/agent-identity-protocol/blob/main/AIP-SPEC.md"
THRESHOLD = "§1.3 step 5"
THRESHOLD_DECLARATION = "§1.3b"
THRESHOLD_FIXTURE = "`threshold-1of3-cosignature`"

HMA_ROW = "| HackMyAgent |"
AIM_ROW = "| AIM |"

POINTERS = [
    ("core.md", "5. **The revocation list format.**", (ATP_REVOCATION, REVOCATION_SCHEMA)),
    ("core.md", "### 3.3 Revocation flow", (ATP_REVOCATION, REVOCATION_SCHEMA)),
    ("core.md", "### 1.5 Declared purpose", (AUTHORIZATION,)),
    ("core.md", "* **ATX is not a runtime authorization system.**", (AUTHORIZATION,)),
    ("README.md", "### An auditor asks what each agent was allowed to attempt", (AUTHORIZATION,)),
    ("core.md", HMA_ROW, (HMA_README,)),
    ("core.md", AIM_ROW, (AIP_TRUST, AIP_SPEC)),
    ("core.md", "8. Issuing node constructs ATX.", (THRESHOLD,)),
    ("core.md", "4. **ATX issuance request.**", (THRESHOLD,)),
    ("docs/conformance.md", "Byte-stable conformance fixtures", (THRESHOLD,)),
    ("sovereign-federation.md", "* 3 HSMs", (THRESHOLD,)),
    ("sovereign-federation.md", "Threshold signing means", (THRESHOLD, THRESHOLD_DECLARATION)),
    ("core.md", "   - Threshold key sets.", (THRESHOLD_DECLARATION,)),
    ("core.md", "**Coverage.**", (THRESHOLD_FIXTURE,)),
]

# Sections that a pointer above cites as where something is defined, and the
# terms each one names.
DEFINITIONS = [
    ("core.md", "### 1.3b ", ("`thresholdKeySets`", "`members`", "`threshold`")),
]

LAB_RE = re.compile(r"lab/forge|\bforge\s+lab\b", re.IGNORECASE)
LAB_CAVEAT = "not an ATX credential"
# The lab, by name, as link text followed by its link target, or as "it", is the
# subject: "you signed" and "a sign" are not.
LAB_SIGNS_RE = re.compile(
    r"\b(?:(?:the\s+)?(?:forge\s+)?lab(?:/forge)?(?:\]\([^)\s]*\))?|it)\s+sign(?:s|ed)\b",
    re.IGNORECASE,
)
HISTORY = {"CHANGELOG.md"}
HISTORY_DIRS = {"errata"}

# Sections whose counts belong to the source they cite.
FIGURES = {("core.md", HMA_ROW), ("core.md", AIM_ROW)}

HEADING_RE = re.compile(r"^(#+)\s")
NEWLINE_RE = re.compile(r"\n")
SENTENCE_END_RE = re.compile(r"(?<=[.!?])\s+")
PERMITTED_RE = re.compile(r"\bpermitted\b", re.IGNORECASE)
ITEM_RE = re.compile(r"^(?:\d+\.|[*+-])\s")
# A section number such as §6.1 is not a count, so a numeral after a dot or a
# section sign does not open one.
COUNT_RE = re.compile(
    r"(?<![\w.§])\d[\d,]*(?:[ -]+[A-Za-z][\w-]*){0,3}?[ -]+(?:checks?|factors?|payloads?|rules?|tests?)\b",
    re.IGNORECASE,
)


def section(lines, start):
    """The lines of the section opened by lines[start]."""
    if lines[start].startswith("|"):
        return lines[start:start + 1]
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


def find_section(root, rel, opening):
    """The index of the line that opens the section and the section's text, its
    lines joined by single spaces. Raises LookupError saying why there is none."""
    path = root / rel
    if not path.is_file():
        raise LookupError(f"file not found; it should hold {opening!r}")
    lines = path.read_text(encoding="utf-8").splitlines()
    start = next((i for i, line in enumerate(lines) if line.startswith(opening)), None)
    if start is None:
        raise LookupError(f"no line opens with {opening!r}")
    return start, " ".join(" ".join(section(lines, start)).split())


def check(root):
    failures = []
    for rel, opening, references in POINTERS:
        try:
            start, body = find_section(root, rel, opening)
        except LookupError as exc:
            failures.append(f"{rel} [pointer] {exc}")
            continue
        for ref in references:
            if ref not in body:
                failures.append(
                    f"{rel}:{start + 1} [pointer] the section opened by {opening!r} does not "
                    f"cite {ref!r}; name where it is specified in the section itself"
                )
        if (rel, opening) in FIGURES:
            for count in COUNT_RE.finditer(body):
                failures.append(
                    f"{rel}:{start + 1} [figure] the section opened by {opening!r} states the "
                    f"count {count.group(0)!r}, which {references[0]} owns; link to it and drop "
                    f"the number"
                )
        if AUTHORIZATION not in references:
            continue
        for sentence in SENTENCE_END_RE.split(body):
            if PERMITTED_RE.search(sentence) and AUTHORIZATION not in sentence:
                failures.append(
                    f"{rel}:{start + 1} [permission] the section opened by {opening!r} calls "
                    f"something permitted without naming {AUTHORIZATION}: {sentence[:100]!r}; "
                    f"say what the credential attests, or that {AUTHORIZATION} decides it"
                )
    for rel, opening, terms in DEFINITIONS:
        try:
            start, body = find_section(root, rel, opening)
        except LookupError as exc:
            failures.append(f"{rel} [definition] {exc}")
            continue
        for term in terms:
            if term not in body:
                failures.append(
                    f"{rel}:{start + 1} [definition] the section opened by {opening!r} does not "
                    f"name {term}, which a pointer cites it for; define it there"
                )
    return failures


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
    """(first line number, text) per paragraph, heading or list item.

    Continuation lines join their block with a newline, so a sentence may wrap
    across a soft line break and still report the line its mention sits on.
    """
    out = []
    start, buf = None, []
    for number, line in enumerate(lines, 1):
        if not line.strip() or HEADING_RE.match(line) or ITEM_RE.match(line.lstrip()):
            if buf:
                out.append((start, "\n".join(buf)))
            start, buf = None, []
            if not line.strip():
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


def says_lab_signs_no_credential(sentence):
    """True when the sentence says the lab signs something and, after that, that
    it is not an ATX credential. The caveat words alone are not the caveat: in
    "rejects anything that is not an ATX credential" they describe something
    else."""
    caveat = sentence.rfind(LAB_CAVEAT)
    signs = LAB_SIGNS_RE.search(sentence)
    return caveat != -1 and signs is not None and signs.start() < caveat


def check_lab(root):
    """Failures, and how many sentences name the forge lab."""
    failures, mentions = [], 0
    for path in markdown_files(root):
        rel = path.relative_to(root).as_posix()
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError as exc:
            failures.append(f"{rel} [lab] not UTF-8 ({exc.reason} at byte {exc.start})")
            continue
        for start, block in blocks(text.splitlines()):
            # Where each newline of the block stands, found once per block and
            # bisected per failure: counting from the start of the block for
            # each failure took time quadratic in the number of failures.
            newlines = None
            for offset, sentence in sentences(block):
                mention = LAB_RE.search(sentence)
                if not mention:
                    continue
                mentions += 1
                if says_lab_signs_no_credential(" ".join(sentence.split())):
                    continue
                if newlines is None:
                    newlines = [m.start() for m in NEWLINE_RE.finditer(block)]
                line = start + bisect.bisect_left(newlines, offset + mention.start())
                failures.append(
                    f"{rel}:{line} [lab] a sentence names the forge lab without saying that "
                    f"what it signs is {LAB_CAVEAT!r}: {' '.join(sentence.split())[:100]!r}; "
                    f"the lab does not verify JCS(TBS) of a real credential, so say so"
                )
    return failures, mentions


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(ROOT), help="tree to check (default: this repository)")
    args = ap.parse_args()
    root = pathlib.Path(args.root).resolve()

    failures = check(root)
    lab_failures, lab_mentions = check_lab(root)
    failures += lab_failures
    if failures:
        print(
            "sections do not name where what they describe is specified, a cited section "
            "does not name what it defines, or a sentence overstates the forge lab:\n",
            file=sys.stderr,
        )
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print(
        f"pointers ok: {len(POINTERS)} section(s) name where what they describe is specified; "
        f"{len(DEFINITIONS)} cited section(s) name what they define; "
        f"{lab_mentions} sentence(s) naming the forge lab say it signs {LAB_CAVEAT!r}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
