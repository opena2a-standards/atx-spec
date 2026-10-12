#!/usr/bin/env python3
"""Assert no text has a signed trust level lowered or reads capabilities as authorization.

core.md section 1.3 says a verifier "MUST NOT lower the level": trustLevel is
inside the signed bytes, so a lower value is a level no issuer signed. A
verifier that holds a credential to less than its signed level says so in a
marker of its own beside that level. core.md section 1.5 says capabilities are
reach, the operations a build is attested to be able to perform, and not
permission: whether an agent may touch a resource is a broker policy decision
under AAP.

Two rules, checked one sentence at a time over every Markdown file in the tree:

  level-lowered           No sentence names a trust level ("trust level",
                          trustLevel) and says it is capped, lowered or
                          downgraded, or that it falls back. A verb counts when
                          it states the act: "capped", "lowered", "downgrade"
                          in any form, "cap", "lower" or "lowering" followed by
                          what is lowered ("cap the", "lowers it"), and "fall
                          back" in any tense. "Level 3 or lower" and "the lower
                          of the two" are comparisons and pass.

  capability-authorized   No sentence names capabilities and uses a verb form
                          of authorize ("the credential authorizes", "human
                          authorized"). The noun passes: a consumer can make an
                          authorization decision on capabilities.

A verb with a denial among the three words before it passes: "MUST NOT lower",
"No verifier lowers", "do not authorize". The denial words are not, never, no,
cannot, nor and without, and a word ending in n't.

A sentence may wrap across lines but does not cross a blank line, a heading, a
list item or a table cell. CHANGELOG.md and errata/ are not checked: they record
what earlier text said, and an erratum quotes the published text verbatim by
design. Hidden directories and node_modules are skipped. A file that is not
UTF-8 fails rather than being skipped.

Each failure is reported as file:line with its rule in brackets.

    python3 scripts/check_signed_fields.py [--root <tree>]

Exit 0 when every file passes, 1 otherwise.
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

LEVEL_RE = re.compile(r"\btrust[\s-]+levels?\b|\btrustLevel\b", re.IGNORECASE)
OBJECT = r"(?:the|a|an|its|their|that|this|each|every|any|it|them)"
LOWERED_RE = re.compile(
    r"\b(?:capped|lowered|downgrad(?:e|es|ed|ing)"
    r"|(?:caps?|capping|lowers?|lowering)\s+" + OBJECT
    + r"|(?:falls?|falling|fell|fallen)\s+back)\b",
    re.IGNORECASE,
)
CAPABILITY_RE = re.compile(r"\bcapabilit(?:y|ies)\b", re.IGNORECASE)
AUTHORIZED_RE = re.compile(r"\bauthori[sz](?:e|es|ed|ing)\b", re.IGNORECASE)

RULES = [
    (
        "level-lowered", LEVEL_RE, LOWERED_RE,
        "in a sentence that names a trust level; a verifier does not change the signed level "
        "(core.md section 1.3), so state a ceiling as the verifier's own marker beside it",
    ),
    (
        "capability-authorized", CAPABILITY_RE, AUTHORIZED_RE,
        "in a sentence that names capabilities; they are attested reach, not permission "
        "(core.md section 1.5), and what an agent may do is a broker policy decision under AAP",
    ),
]

DENIALS = {"not", "never", "no", "cannot", "nor", "without"}
DENIAL_REACH = 3
WORD_RE = re.compile(r"\S+")
WORD_EDGE = "`*_\"'()[],;:"
SENTENCE_END_RE = re.compile(r"(?<=[.!?])\s+")
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

    Continuation lines join their block with a newline, so a sentence may wrap
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


def sentences(block):
    """(offset, sentence) pairs for a block; a table row is read one cell at a time."""
    parts = block.split("|") if block.lstrip().startswith("|") else [block]
    offset = 0
    for part in parts:
        pos = 0
        for m in SENTENCE_END_RE.finditer(part):
            yield offset + pos, part[pos:m.start()]
            pos = m.end()
        if pos < len(part):
            yield offset + pos, part[pos:]
        offset += len(part) + 1


def stated(sentence, verb_re):
    """The first match of verb_re in sentence that no denial governs, or None."""
    words = [(m.end(), m.group(0).strip(WORD_EDGE).lower()) for m in WORD_RE.finditer(sentence)]
    at = 0  # how many words end before the verb; verbs come in order, so it only grows
    for verb in verb_re.finditer(sentence):
        while at < len(words) and words[at][0] <= verb.start():
            at += 1
        before = words[max(0, at - DENIAL_REACH):at]
        if not any(word in DENIALS or word.endswith("n't") for _, word in before):
            return verb
    return None


def check_file(rel, text):
    failures = []
    for first, block in blocks(text.splitlines()):
        line, counted = first, 0
        for offset, sentence in sentences(block):
            # Offsets only grow, so each newline is counted once per block.
            line += block.count("\n", counted, offset)
            counted = offset
            for rule, subject_re, verb_re, why in RULES:
                if not subject_re.search(sentence):
                    continue
                verb = stated(sentence, verb_re)
                if verb is None:
                    continue
                at = line + sentence.count("\n", 0, verb.start())
                failures.append(f"{rel}:{at} [{rule}] {' '.join(verb.group(0).split())!r} {why}")
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
        print("text disagrees with core.md on the signed trust level or on capabilities:\n",
              file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print(
        f"signed fields ok: {len(files)} Markdown file(s) checked, none lowers a signed trust "
        f"level or reads capabilities as authorization"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
