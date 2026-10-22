#!/usr/bin/env python3
"""Assert that core.md section 1.3a.2 says how the TBS writes each timestamp.

core.md section 1.3a.2 lists the members of the v1.1 to-be-signed (TBS) object
in the "The included keys are exactly:" block, and
schemas/atx-credential-v1.1.schema.json types them. A TBS member, at any depth,
that the schema types with format date-time is a timestamp: an RFC 3339 value
that can carry a numeric time-zone offset and a fractional second, so two
implementations write the same text for it into the TBS only when the section
says which text that is. A verifier that carries the wire string verbatim and
one that writes it in UTC to whole seconds sign or verify different bytes for a
value written with a numeric offset or a fractional second. The schema is walked
through properties, items, additionalProperties, oneOf, anyOf, allOf and local
$ref.

  missing   For each such member, a sentence of section 1.3a.2 names it in
            backticks, as `member` or as a dotted path such as `parent.member`,
            and says "UTC" and "whole second" or "whole seconds". A sentence
            outside the section does not count.
  none      The schema types at least one TBS member with format date-time, so
            a schema the check cannot read that way fails instead of passing.
  keys      Section 1.3a.2 lists the included keys in a fenced block after the
            line that says "included keys are exactly".

With --suite, each jcs-vectors/vectors/*.json of an atx-conformance checkout is
also read: its expected.canonicalHex is decoded and parsed as JSON, and a value
of one of those members that is not a string of the form YYYY-MM-DDTHH:MM:SSZ
fails as [vector], as does a TBS without one of them that is a top-level key. A
member inside an object the TBS holds as null, such as the generatedAt of a
null behavioralProfile, is not looked for. A vector that cannot be read that
way fails as [vector], and so does a checkout with no vectors.

A sentence may wrap across lines but does not cross a blank line, a heading, a
list item or a table cell, and a sentence does not end inside a code span.
Fenced code blocks are not read as sentences.

A tree fails with a message that says why when core.md is missing, is not UTF-8
or has no section 1.3a.2 heading, and when the schema is missing or is not JSON.
Every other failure is reported with its rule in brackets, as file:line, or as
the file alone for a vector.

    python3 scripts/check_tbs_timestamps.py [--root <tree>] [--suite <atx-conformance>]

Exit 0 when every check passes, 1 when one fails, 2 on a usage error.
"""

import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMA = "schemas/atx-credential-v1.1.schema.json"
DATE_TIME = "date-time"

SECTION_RE = re.compile(r"^(#{1,6})\s+1\.3a\.2(?![\w.])")
HEADING_RE = re.compile(r"^(#{1,6})\s")
KEYS_LEAD_RE = re.compile(r"included keys are exactly", re.IGNORECASE)
FENCE_RE = re.compile(r"^\s*(?:```|~~~)")
PARENTHESES_RE = re.compile(r"\([^)]*\)")
NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
MEMBER_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*")

UTC_RE = re.compile(r"\bUTC\b", re.IGNORECASE)
WHOLE_SECONDS_RE = re.compile(r"\bwhole\s+seconds?\b", re.IGNORECASE)
# What a timestamp in UTC to whole seconds looks like in the TBS.
PROJECTED_RE = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", re.ASCII)

CODE_RE = re.compile(r"`([^`]+)`")
SENTENCE_END_RE = re.compile(r"(?<=[.!?])\s+")
BLOCK_START_RE = re.compile(r"^\s*(?:#+\s|\d+\.\s|[-*+]\s|\|)")


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


def projection_names(lines, start, end):
    """The member-shaped code spans of each sentence of lines[start:end] that says
    "UTC" and "whole seconds"; start and end are line numbers, end excluded."""
    names = set()
    for _, block in blocks(lines[start - 1:end - 1]):
        for sentence in sentences(block):
            if not UTC_RE.search(sentence) or not WHOLE_SECONDS_RE.search(sentence):
                continue
            for code in CODE_RE.finditer(sentence):
                name = code.group(1).strip()
                if MEMBER_RE.fullmatch(name):
                    names.add(name)
    return names


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


def date_time_members(schema):
    """Sorted dotted paths of every member the schema types with format date-time, at any depth."""
    found = set()

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
        if path and node.get("format") == DATE_TIME:
            found.add(path)
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
    return sorted(found)


def refers_to(name, path):
    """True when a name in backticks names the member at path: the path itself or its tail."""
    return name == path or path.endswith("." + name)


def values_at(node, parts):
    """Each value at the dotted path parts below node; array positions add nothing,
    and a path whose parent is not an object yields nothing."""
    if isinstance(node, list):
        for item in node:
            yield from values_at(item, parts)
    elif not parts:
        yield node
    elif isinstance(node, dict) and parts[0] in node:
        yield from values_at(node[parts[0]], parts[1:])


def check_suite(suite, members):
    """(vectors read, timestamp values read, failures) for the suite's jcs-vectors."""
    vectors = sorted((suite / "jcs-vectors" / "vectors").glob("*.json"))
    if not vectors:
        return 0, 0, [f"{suite} [vector] has no jcs-vectors/vectors/*.json; refusing to pass "
                      f"vacuously"]
    failures, read = [], 0
    for path in vectors:
        rel = path.relative_to(suite).as_posix()
        try:
            doc = json.loads(path.read_text(encoding="utf-8"))
            tbs = json.loads(bytes.fromhex(doc["expected"]["canonicalHex"]).decode("utf-8"))
        except (OSError, ValueError, KeyError, TypeError) as exc:
            failures.append(f"{rel} [vector] cannot read expected.canonicalHex as JSON: {exc}")
            continue
        if not isinstance(tbs, dict):
            failures.append(f"{rel} [vector] expected.canonicalHex is not a JSON object")
            continue
        for member in members:
            if "." not in member and member not in tbs:
                failures.append(f"{rel} [vector] leaves the TBS key `{member}` out of its TBS")
                continue
            for value in values_at(tbs, member.split(".")):
                read += 1
                if not isinstance(value, str) or not PROJECTED_RE.fullmatch(value):
                    failures.append(
                        f"{rel} [vector] holds `{member}` as {json.dumps(value)}, which is not "
                        f"written in UTC to whole seconds (YYYY-MM-DDTHH:MM:SSZ)"
                    )
    return len(vectors), read, failures


def main():
    ap = argparse.ArgumentParser(
        description="Assert that core.md section 1.3a.2 says how the TBS writes each timestamp."
    )
    ap.add_argument("--root", default=str(ROOT), help="tree to check (default: this repository)")
    ap.add_argument("--suite", help="atx-conformance checkout whose jcs-vectors are also read")
    args = ap.parse_args()
    root = pathlib.Path(args.root).resolve()
    suite = pathlib.Path(args.suite).resolve() if args.suite else None
    if suite is not None and not suite.is_dir():
        print(f"--suite {args.suite}: not a directory", file=sys.stderr)
        return 2

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
    members = [path for path in date_time_members(schema) if path.split(".")[0] in key_lines]

    failures = []
    if not members:
        failures.append(
            f"core.md:{heading} [none] {SCHEMA} types no TBS member with format date-time, so "
            f"there is no timestamp to find a projection for; refusing to pass vacuously"
        )
    stated = projection_names(lines, heading, end)
    for path in members:
        if not any(refers_to(name, path) for name in stated):
            failures.append(
                f"core.md:{key_lines[path.split('.')[0]]} [missing] section 1.3a.2 does not say "
                f"how the TBS writes `{path}`, which the schema types as an RFC 3339 date-time: "
                f"no sentence of the section names it in backticks and says \"UTC\" and "
                f"\"whole seconds\""
            )

    vectors = read = 0
    if suite is not None:
        vectors, read, vector_failures = check_suite(suite, members)
        failures.extend(vector_failures)

    if failures:
        print("a TBS timestamp has no stated projection, or a vector writes one another way:\n",
              file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    summary = (f"TBS timestamps ok: section 1.3a.2 says the TBS writes each of the "
               f"{len(members)} TBS member(s) the schema types as a date-time "
               f"({', '.join(members)}) in UTC to whole seconds")
    if suite is not None:
        summary += (f"; {vectors} jcs-vector(s) hold {read} such value(s), each "
                    f"YYYY-MM-DDTHH:MM:SSZ")
    print(summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
