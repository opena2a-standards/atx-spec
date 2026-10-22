#!/usr/bin/env python3
"""Assert that core.md section 1.3a.2 says what becomes of a member outside each closed TBS object.

core.md section 1.3a.2 lists the members of the v1.1 to-be-signed (TBS) object
in the "The included keys are exactly:" block, and
schemas/atx-credential-v1.1.schema.json types them. A TBS key whose own schema
node (a local $ref is followed; oneOf, anyOf and allOf are not) has "object"
among its types, lists its members under properties and sets
additionalProperties to false is a closed object. The projection writes only
the members the section names for it, so a member with any other name is in no
signed byte: a verifier that drops it while rebuilding the TBS accepts a
credential that carries a member no signature covers. The schema's
additionalProperties does not settle this, because a verifier is not required to
apply the schema, so the section has to.

  unstated  For each closed object, a sentence of section 1.3a.2 names it in
            backticks, names in backticks every member the schema lists under
            its properties, and says "exactly", "none of", "no other" or "any
            other".
  outcome   The list item or paragraph that holds that sentence also holds a
            sentence that names the closed object in backticks and says either
            "reject" (or "rejects", "rejected") and SIGNATURE_INVALID, or
            "verbatim".
  none      The schema types at least one TBS key as a closed object, so a
            schema the check cannot read that way fails instead of passing.
  keys      Section 1.3a.2 lists the included keys in a fenced block after the
            line that says "included keys are exactly".

The check reads words, not meaning: it finds the sentences that state a closed
member set and an outcome, and review decides what they say.

A sentence may wrap across lines but does not cross a blank line, a heading, a
list item or a table cell, and a sentence does not end inside a code span.
Fenced code blocks are not read as sentences.

A tree fails with a message that says why when core.md is missing, is not UTF-8
or has no section 1.3a.2 heading, and when the schema is missing or is not JSON.
Every other failure is reported as file:line with its rule in brackets.

    python3 scripts/check_tbs_member_names.py [--root <tree>]

Exit 0 when every check passes, 1 when one fails, 2 on a usage error.
"""

import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMA = "schemas/atx-credential-v1.1.schema.json"

SECTION_RE = re.compile(r"^(#{1,6})\s+1\.3a\.2(?![\w.])")
HEADING_RE = re.compile(r"^(#{1,6})\s")
KEYS_LEAD_RE = re.compile(r"included keys are exactly", re.IGNORECASE)
FENCE_RE = re.compile(r"^\s*(?:```|~~~)")
PARENTHESES_RE = re.compile(r"\([^)]*\)")
NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

# A sentence that closes a member set, and the two outcomes for a member outside it.
CLOSED_RE = re.compile(r"\bexactly\b|\bnone\s+of\b|\bno\s+other\b|\bany\s+other\b", re.IGNORECASE)
REJECT_RE = re.compile(r"\breject(?:s|ed)?\b", re.IGNORECASE)
SIGNATURE_INVALID = "SIGNATURE_INVALID"
VERBATIM_RE = re.compile(r"\bverbatim\b", re.IGNORECASE)

CODE_RE = re.compile(r"`([^`]+)`")
SENTENCE_END_RE = re.compile(r"(?<=[.!?])\s+")
BLOCK_START_RE = re.compile(r"^\s*(?:#+\s|\d+\.\s|[-*+]\s|\|)")


def blocks(lines):
    """(first line number, text) per paragraph, list item, heading or table row.

    Continuation lines join their block with a newline, so a sentence may wrap
    across a soft line break. The lines of a fenced code block belong to no
    block.
    """
    out = []
    start, buf = None, []
    fenced = False
    for number, line in enumerate(lines, 1):
        if FENCE_RE.match(line):
            fenced = not fenced
            if buf:
                out.append((start, "\n".join(buf)))
            start, buf = None, []
            continue
        if fenced:
            continue
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
    """Each sentence of a block; a table row is read one cell at a time."""
    parts = block.split("|") if block.lstrip().startswith("|") else [block]
    for part in parts:
        spans = [m.span() for m in CODE_RE.finditer(part)]
        pos = 0
        for m in SENTENCE_END_RE.finditer(part):
            if any(a < m.start() < b for a, b in spans):
                continue
            yield part[pos:m.start()]
            pos = m.end()
        if pos < len(part):
            yield part[pos:]


def section_range(lines):
    """(heading line, first line after the section) of core.md section 1.3a.2, or None."""
    for number, line in enumerate(lines, 1):
        m = SECTION_RE.match(line)
        if not m:
            continue
        level = len(m.group(1))
        fenced = False
        for later in range(number, len(lines)):
            if FENCE_RE.match(lines[later]):
                fenced = not fenced
                continue
            h = None if fenced else HEADING_RE.match(lines[later])
            if h and len(h.group(1)) <= level:
                return number, later + 1
        return number, len(lines) + 1
    return None


def included_keys(lines, start, end):
    """(line, key) per key of the fenced block after "included keys are exactly", or None."""
    for number in range(start, end):
        if not KEYS_LEAD_RE.search(lines[number - 1]):
            continue
        at = number
        while at < end - 1 and not FENCE_RE.match(lines[at]):
            if lines[at].strip():
                return None  # prose between the lead and its block
            at += 1
        if at >= end - 1:
            return None
        keys = []
        for inner in range(at + 1, end - 1):
            if FENCE_RE.match(lines[inner]):
                return keys
            for name in NAME_RE.findall(PARENTHESES_RE.sub("", lines[inner])):
                keys.append((inner + 1, name))
        return None
    return None


def closed_members(schema, key):
    """Sorted member names of the schema's node for a top-level key when it is a closed
    object, or None: "object" among its types, properties listed, additionalProperties false."""
    properties = schema.get("properties") if isinstance(schema, dict) else None
    node = properties.get(key) if isinstance(properties, dict) else None
    seen = set()
    while isinstance(node, dict) and "$ref" in node:
        ref = node["$ref"]
        if not isinstance(ref, str) or not ref.startswith("#/") or ref in seen:
            return None
        seen.add(ref)
        target = schema
        for part in ref[2:].split("/"):
            target = target.get(part) if isinstance(target, dict) else None
        node = target
    if not isinstance(node, dict):
        return None
    types = node.get("type")
    types = types if isinstance(types, list) else [types]
    members = node.get("properties")
    if ("object" not in types or not isinstance(members, dict) or not members
            or node.get("additionalProperties") is not False):
        return None
    return sorted(members)


def code_names(sentence):
    """The text of each code span of a sentence, stripped."""
    return {m.group(1).strip() for m in CODE_RE.finditer(sentence)}


def states_outcome(sentence, key):
    """True when a sentence names key in backticks and says reject and SIGNATURE_INVALID,
    or says verbatim."""
    if key not in code_names(sentence):
        return False
    rejects = REJECT_RE.search(sentence) and SIGNATURE_INVALID in sentence
    return bool(rejects or VERBATIM_RE.search(sentence))


def check_key(lines, start, end, key, members):
    """(closed-set sentence found, its block's first line, outcome stated) for one closed object.

    The first block of lines[start:end] whose closed-set sentence also has an outcome
    sentence wins; otherwise the first block with a closed-set sentence is reported.
    """
    first = None
    for number, block in blocks(lines[start - 1:end - 1]):
        texts = list(sentences(block))
        closes = any(
            key in code_names(s) and set(members) <= code_names(s) and CLOSED_RE.search(s)
            for s in texts
        )
        if not closes:
            continue
        line = start + number - 1
        if any(states_outcome(s, key) for s in texts):
            return True, line, True
        if first is None:
            first = line
    return first is not None, first, False


def main():
    ap = argparse.ArgumentParser(
        description="Assert that core.md section 1.3a.2 says what becomes of a member outside "
                    "each closed TBS object."
    )
    ap.add_argument("--root", default=str(ROOT), help="tree to check (default: this repository)")
    args = ap.parse_args()
    root = pathlib.Path(args.root).resolve()

    core_path, schema_path = root / "core.md", root / SCHEMA
    for path in (core_path, schema_path):
        if not path.is_file():
            print(f"{path.relative_to(root).as_posix()} not found under {root}; cannot check",
                  file=sys.stderr)
            return 1
    try:
        core = core_path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError) as exc:
        print(f"core.md cannot be read as UTF-8 text: {exc}", file=sys.stderr)
        return 1
    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
    except (ValueError, OSError) as exc:
        print(f"{SCHEMA} cannot be read as JSON: {exc}", file=sys.stderr)
        return 1

    lines = core.splitlines()
    section = section_range(lines)
    if section is None:
        print("core.md has no section 1.3a.2 heading; cannot find the TBS members",
              file=sys.stderr)
        return 1
    heading, end = section
    keys = included_keys(lines, heading, end)
    if not keys:
        print(f"core.md:{heading} [keys] section 1.3a.2 lists no included keys in a fenced block "
              f"after \"included keys are exactly\"", file=sys.stderr)
        return 1
    key_lines = {}
    for line, key in keys:
        key_lines.setdefault(key, line)
    closed = {}
    for key in key_lines:
        members = closed_members(schema, key)
        if members is not None:
            closed[key] = members

    failures = []
    if not closed:
        failures.append(
            f"core.md:{heading} [none] {SCHEMA} types no TBS key as an object with "
            f"additionalProperties false, so there is no closed member set to find a statement "
            f"for; refusing to pass vacuously"
        )
    for key, members in closed.items():
        names = ", ".join(f"`{m}`" for m in members)
        found, line, outcome = check_key(lines, heading, end, key, members)
        if not found:
            failures.append(
                f"core.md:{key_lines[key]} [unstated] section 1.3a.2 does not say which members "
                f"`{key}` may hold: no sentence of the section names `{key}` and each of {names} "
                f"in backticks and says \"exactly\", \"none of\", \"no other\" or \"any other\", "
                f"so a member with another name is in no signed byte and the text gives no "
                f"outcome for it"
            )
        elif not outcome:
            failures.append(
                f"core.md:{line} [outcome] section 1.3a.2 names the members `{key}` may hold but "
                f"states no outcome for any other: no sentence of that rule names `{key}` in "
                f"backticks and says \"reject\" and {SIGNATURE_INVALID}, or \"verbatim\""
            )

    if failures:
        print("a closed TBS object has no stated outcome for a member outside it:\n",
              file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print(f"TBS member names ok: section 1.3a.2 states the members of each of the {len(closed)} "
          f"TBS key(s) the schema types as a closed object ({', '.join(closed)}) and the "
          f"outcome for any other")
    return 0


if __name__ == "__main__":
    sys.exit(main())
