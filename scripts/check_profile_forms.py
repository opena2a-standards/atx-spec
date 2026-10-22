#!/usr/bin/env python3
"""Assert that core.md section 1.3a.2 states the form of each behavioralProfile member.

core.md section 1.3a.2 rule 1 says when a present behavioralProfile is well
formed, and a verifier rejects one that is not as a signature failure, so two
verifiers agree on a credential only when the text says, for each member, which
JSON values are in its form. schemas/atx-credential-v1.1.schema.json names the
members and types them. A member the schema types as integer is an integer
member: JSON Schema's integer type accepts 14.0 and 1.4e1 (jsonschema 4.26.0,
draft 2020-12), and Go's encoding/json rejects both when it decodes them into an
int (go1.26.3), so the type alone does not decide them. A string member with
format date-time is a date-time member: the RFC 3339 grammar admits a numeric
offset and fractional seconds, and the projection writes the member in UTC to
whole seconds, so the text has to say what becomes of each.

Three rules, each reported as core.md:line with its rule in brackets:

  integer-form    The sentences of section 1.3a.2 that name an integer member in
                  backticks hold "fraction" and "exponent" between them, so they
                  say how a number written with a fraction part or an exponent
                  part is decided.
  date-time-form  The sentences of section 1.3a.2 that name a date-time member
                  in backticks hold "RFC 3339", "offset" and "fraction" between
                  them, so they name the grammar and say what becomes of a
                  numeric offset and of fractional seconds.
  deferred        A sentence of rule 1 that decides a member as another member
                  is decided or read ("decided as", "as it reads", "as the
                  verifier decides", "as the verifier reads") names, in
                  backticks after those words and before the next
                  behavioralProfile member it names, at least one member the
                  schema defines. Each is of the kind of the behavioralProfile
                  member named last before the words (of either kind when the
                  sentence names none there), and the sentences of core.md that
                  name it hold the words its kind asks for above.

A member whose every deferral in rule 1 passes needs no statement of its own,
since rule 1 then points to text that states its form; a member with no passing
deferral and no statement fails integer-form or date-time-form, and a deferral
that fails is reported as deferred as well.

A member is named in backticks as `member` or as a dotted path such as
`behavioralProfile.member`. Words are matched in any letter case, and
"fraction" also matches "fractional". Rule 1 is the list item of section 1.3a.2
that begins "1." at the start of a line; it runs to the next line that is
neither blank nor indented, so its indented bullets belong to it. A
behavioralProfile member is a property of behavioralProfile in the schema, which
is walked through properties, items, additionalProperties, oneOf, anyOf, allOf
and local $ref.

A sentence may wrap across lines but does not cross a blank line, a heading, a
list item or a table cell, and a sentence does not end inside a code span.
Fenced code blocks are not read.

A tree fails with a message that says why when core.md is missing, is not UTF-8,
has no section 1.3a.2 heading or no rule 1 in that section, when the schema is
missing or is not JSON, and when the schema defines no behavioralProfile member,
so a renamed section or member cannot pass vacuously.

    python3 scripts/check_profile_forms.py [--root <tree>]

Exit 0 when every check passes, 1 when one fails, 2 on a usage error.
"""

import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMA = "schemas/atx-credential-v1.1.schema.json"
PROFILE = "behavioralProfile"

SECTION_RE = re.compile(r"^(#{1,6})\s+1\.3a\.2(?![\w.])")
HEADING_RE = re.compile(r"^(#{1,6})\s")
FENCE_RE = re.compile(r"^\s*(?:```|~~~)")
RULE_ONE_RE = re.compile(r"^1\.\s")
MEMBER_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*")
CODE_RE = re.compile(r"`([^`]+)`")
SENTENCE_END_RE = re.compile(r"(?<=[.!?])\s+")
BLOCK_START_RE = re.compile(r"^\s*(?:#+\s|\d+\.\s|[-*+]\s|\|)")
DEFER_RE = re.compile(
    r"\bdecided\s+as\b|\bas\s+(?:it|the\s+verifier)\s+(?:decides|reads)\b", re.IGNORECASE
)

# The words the statement of each kind of form holds, each with what it says.
FORMS = {
    "integer": (
        (re.compile(r"\bfraction", re.IGNORECASE),
         "how it decides a number written with a fraction part (14.0)"),
        (re.compile(r"\bexponent", re.IGNORECASE),
         "how it decides a number written with an exponent part (1.4e1)"),
    ),
    "date-time": (
        (re.compile(r"\bRFC\s*3339\b", re.IGNORECASE), "which grammar it matches (RFC 3339)"),
        (re.compile(r"\boffset", re.IGNORECASE), "what becomes of a numeric offset"),
        (re.compile(r"\bfraction", re.IGNORECASE), "what becomes of fractional seconds"),
    ),
}
KIND_NAMES = {"integer": "integer", "date-time": "a date-time string"}


def blocks(lines):
    """(first line number, text) per paragraph, list item, heading or table row.

    Continuation lines join their block with a newline, so a sentence may wrap
    across a soft line break and still report the line a word sits on. The
    lines of a fenced code block belong to no block.
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
    """(offset, sentence) pairs for a block; a table row is read one cell at a time."""
    parts = block.split("|") if block.lstrip().startswith("|") else [block]
    offset = 0
    for part in parts:
        spans = [m.span() for m in CODE_RE.finditer(part)]
        pos = 0
        for m in SENTENCE_END_RE.finditer(part):
            if any(a < m.start() < b for a, b in spans):
                continue
            yield offset + pos, part[pos:m.start()]
            pos = m.end()
        if pos < len(part):
            yield offset + pos, part[pos:]
        offset += len(part) + 1


def all_sentences(text):
    """(line, sentence, [(offset, name)]) per sentence; the names are its member-shaped
    code spans, each with its offset in the sentence."""
    out = []
    for first, block in blocks(text.splitlines()):
        for offset, sentence in sentences(block):
            line = first + block.count("\n", 0, offset)
            names = []
            for code in CODE_RE.finditer(sentence):
                name = code.group(1).strip()
                if MEMBER_RE.fullmatch(name):
                    names.append((code.start(), name))
            out.append((line, sentence, names))
    return out


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


def rule_one_range(lines, start, end):
    """(first line, first line after) of rule 1 within [start, end), or None.

    Rule 1 begins with "1." at the start of a line and runs to the next line
    that is neither blank nor indented.
    """
    fenced = False
    for number in range(start, end):
        line = lines[number - 1]
        if FENCE_RE.match(line):
            fenced = not fenced
            continue
        if fenced or not RULE_ONE_RE.match(line):
            continue
        for later in range(number + 1, end):
            text = lines[later - 1]
            if text.strip() and not text[0].isspace():
                return number, later
        return number, end
    return None


def schema_members(schema):
    """{dotted path: (set of JSON types, set of formats)} for every member the schema
    defines, at any depth."""
    found = {}

    def resolve(node, seen):
        while isinstance(node, dict) and "$ref" in node:
            ref = node["$ref"]
            if not isinstance(ref, str) or not ref.startswith("#/") or ref in seen:
                return None, seen
            seen = seen | {ref}
            target = schema
            for part in ref[2:].split("/"):
                target = target.get(part) if isinstance(target, dict) else None
            node = target
        return node, seen

    def walk(node, path, seen):
        node, seen = resolve(node, seen)
        if not isinstance(node, dict):
            return
        if path:
            types, formats = found.setdefault(path, (set(), set()))
            kind = node.get("type", [])
            if isinstance(kind, str):
                types.add(kind)
            elif isinstance(kind, list):
                types.update(k for k in kind if isinstance(k, str))
            if isinstance(node.get("format"), str):
                formats.add(node["format"])
        for key in ("oneOf", "anyOf", "allOf"):
            subs = node.get(key, [])
            for sub in subs if isinstance(subs, list) else []:
                walk(sub, path, seen)
        properties = node.get("properties", {})
        if isinstance(properties, dict):
            for name, sub in properties.items():
                walk(sub, f"{path}.{name}" if path else name, seen)
        for key in ("items", "additionalProperties"):
            if isinstance(node.get(key), dict):
                walk(node[key], path, seen)

    walk(schema, "", frozenset())
    return found


def kind_of(types, formats):
    """"integer", "date-time" or None for a member's JSON types and formats."""
    if "integer" in types:
        return "integer"
    if "string" in types and "date-time" in formats:
        return "date-time"
    return None


def refers_to(name, path):
    """True when a name in backticks names the member at path: the path itself or its tail."""
    return name == path or path.endswith("." + name)


def missing(kind, texts):
    """What the sentences in texts leave unsaid of a form of this kind, one item per word."""
    return [says for pattern, says in FORMS[kind] if not any(pattern.search(t) for t in texts)]


def join_or(items):
    return items[0] if len(items) == 1 else f"{', '.join(items[:-1])} or {items[-1]}"


def short(path):
    return path.rsplit(".", 1)[-1]


def check_deferrals(rule_sentences, core_sentences, profile, members):
    """(failures, {profile path: True when a deferral of it passes, False when one fails},
    number of deferrals) for the deferrals in the sentences of rule 1."""
    failures, outcome, count = [], {}, 0
    for line, sentence, names in rule_sentences:
        for m in DEFER_RE.finditer(sentence):
            count += 1
            at = line + sentence.count("\n", 0, m.start())
            phrase = " ".join(m.group(0).split())
            before = [n for pos, n in names if pos < m.start()
                      and any(refers_to(n, p) for p in profile)]
            deferring = None
            if before:
                deferring = next(p for p in profile if refers_to(before[-1], p))
            who = f"`{short(deferring)}`" if deferring else "a member"
            targets = []
            for pos, name in names:
                if pos < m.end():
                    continue
                if any(refers_to(name, p) for p in profile):
                    break
                paths = [p for p in members if refers_to(name, p)]
                if paths:
                    targets.append((name, paths))
            passed = True
            if not targets:
                failures.append(
                    f"core.md:{at} [deferred] decides {who} by reference (\"{phrase}\") but names "
                    f"no member of the schema in backticks after those words, so the text it "
                    f"defers to cannot be found"
                )
                passed = False
            for name, paths in targets:
                kinds = {kind_of(*members[p]) for p in paths} - {None}
                want = profile.get(deferring) if deferring else None
                if want and want not in kinds:
                    got = (" or ".join(sorted(KIND_NAMES[k] for k in kinds))
                           or "neither integer nor a date-time string")
                    failures.append(
                        f"core.md:{at} [deferred] decides {who} as `{name}` is decided, but the "
                        f"schema types `{name}` as {got}, not as {KIND_NAMES[want]}"
                    )
                    passed = False
                    continue
                if not want:
                    if len(kinds) != 1:
                        failures.append(
                            f"core.md:{at} [deferred] defers to `{name}`, which the schema types "
                            f"as neither integer nor a date-time string, so no form can be read "
                            f"for it"
                        )
                        passed = False
                        continue
                    want = next(iter(kinds))
                texts = [s for _, s, ns in core_sentences
                         if any(refers_to(n, p) for _, n in ns for p in paths)]
                gaps = missing(want, texts)
                if gaps:
                    failures.append(
                        f"core.md:{at} [deferred] decides {who} as `{name}` is decided, but no "
                        f"sentence of core.md that names `{name}` says {join_or(gaps)}"
                    )
                    passed = False
            if deferring:
                outcome[deferring] = outcome.get(deferring, True) and passed
    return failures, outcome, count


def main():
    ap = argparse.ArgumentParser(
        description="Assert that core.md section 1.3a.2 states the form of each "
                    "behavioralProfile member."
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
        print("core.md has no section 1.3a.2 heading; cannot find rule 1", file=sys.stderr)
        return 1
    heading, end = section
    rule = rule_one_range(lines, heading + 1, end)
    if rule is None:
        print(f"core.md:{heading} [rule] section 1.3a.2 has no rule 1, a list item that begins "
              f"\"1.\" at the start of a line", file=sys.stderr)
        return 1
    rule_start, rule_end = rule

    members = schema_members(schema) if isinstance(schema, dict) else {}
    in_profile = sorted(p for p in members if p.startswith(PROFILE + ".") and p.count(".") == 1)
    if not in_profile:
        print(f"{SCHEMA} [members] defines no {PROFILE} member; refusing to pass vacuously",
              file=sys.stderr)
        return 1
    profile = {p: kind_of(*members[p]) for p in in_profile}
    profile = {p: k for p, k in profile.items() if k}

    core_sentences = all_sentences(core)
    section_sentences = [s for s in core_sentences if heading <= s[0] < end]
    rule_sentences = [s for s in core_sentences if rule_start <= s[0] < rule_end]

    failures, deferred, deferrals = check_deferrals(rule_sentences, core_sentences,
                                                    {p: profile.get(p) for p in in_profile},
                                                    members)
    for path, kind in profile.items():
        texts = [s for _, s, names in section_sentences
                 if any(refers_to(n, path) for _, n in names)]
        gaps = missing(kind, texts)
        if not gaps or deferred.get(path):
            continue
        name = short(path)
        if kind == "integer":
            failures.append(
                f"core.md:{rule_start} [integer-form] no sentence of section 1.3a.2 that names "
                f"`{name}`, which the schema types as integer, says {join_or(gaps)}, and rule 1 "
                f"defers its form to no member whose form core.md states; JSON Schema's integer "
                f"type accepts 14.0 and Go's encoding/json rejects it when it decodes into an "
                f"int, so the type alone does not decide it"
            )
        else:
            failures.append(
                f"core.md:{rule_start} [date-time-form] no sentence of section 1.3a.2 that names "
                f"`{name}`, which the schema types as a date-time string, says {join_or(gaps)}, "
                f"and rule 1 defers its form to no member whose form core.md states"
            )

    if failures:
        print("section 1.3a.2 leaves the form of a behavioralProfile member undecided:\n",
              file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    names = ", ".join(short(p) for p in profile) or "none"
    print(f"profile forms ok: section 1.3a.2 states, or rule 1 defers to text that states, the "
          f"form of each of the {len(profile)} {PROFILE} member(s) the schema types as integer "
          f"or as a date-time string ({names}); rule 1 holds {deferrals} deferral(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
