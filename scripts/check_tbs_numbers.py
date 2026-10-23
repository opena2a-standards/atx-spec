#!/usr/bin/env python3
"""Assert that a sentence naming the only JSON numbers in the TBS names each one, that
the schema and core.md bound each to integers of absolute value at most 2^53 - 1, and
that core.md gives the outcome for a JSON number in a member the TBS carries verbatim.

core.md section 1.3a.2 rule 3 string-encodes trustScore in the v1.1
to-be-signed (TBS) object and then says which JSON numbers the TBS still holds.
Two other places fix which ones those are: the "The included keys are exactly:"
block of section 1.3a.2 lists the members of the TBS, and
schemas/atx-credential-v1.1.schema.json types them. A TBS member, at any depth,
that the schema types as integer or number holds a JSON number in the TBS,
except trustScore, which rule 3 converts to a string. The schema is walked
through properties, items, additionalProperties, oneOf, anyOf, allOf and local
$ref.

A sentence states the only JSON numbers in the TBS when it names the TBS ("TBS"
or "to-be-signed") and says which JSON numbers it holds and no others: "only",
"sole" or "no other" up to three words before "JSON number" or "JSON numbers"
("the only JSON numbers", "only integers as JSON numbers"), or "JSON number" or
"JSON numbers" followed by "other than", "besides", "apart from" or "except".
Each such sentence, in every Markdown file of the tree, is checked:

  missing        It names each of those members in backticks, as `member` or as
                 a dotted path such as `parent.member`.
  not-a-number   No name in backticks in it is a member the TBS does not hold as
                 a JSON number: trustScore, a member the TBS leaves out, or a
                 member of another type. The name of an object that holds one of
                 them (`scanSummary`) passes, and a name the schema does not
                 define (`null`) is not read as a member.
  absent         core.md section 1.3a.2 holds at least one such sentence, so a
                 rewording the check cannot read fails instead of passing.
  keys           Section 1.3a.2 lists the included keys in a fenced block after
                 the line that says "included keys are exactly", and the schema
                 defines each of them.

Rule 3 says the RFC 8785 ECMAScript number-formatting path is out of scope
because those members are integers, which holds only for an integer whose
absolute value is at most 9007199254740991 (2^53 - 1): implementations agree
exactly on the value of such an integer (RFC 8259 section 6), and RFC 8785
writes it in decimal with neither a fraction nor an exponent part. Two more
checks hold the schema and the text to that range:

  unbounded      Each schema node that types one of those members as integer or
                 number types it as integer, with a minimum (or exclusiveMinimum)
                 that admits no integer below -9007199254740991 and a maximum (or
                 exclusiveMaximum) that admits none above 9007199254740991.
  range          Section 1.3a.2 holds a sentence that says "9007199254740991"
                 and "reject", the verifier's outcome for a member outside that
                 range, and names neither of the members the verbatim check
                 reads: a sentence that names one gives the outcome for a JSON
                 number inside it, not for those members.

Rules 5 and 6 carry a present declaredPurpose and a present
scanSummary.techniques into the TBS verbatim, whatever they hold, so a
credential that is not conforming can carry a JSON number there, at any depth,
that rule 3's bound does not reach: one written with a fraction or an exponent
part, or of absolute value above 9007199254740991. One more check holds the
text to an outcome for such a number:

  verbatim       For each of declaredPurpose and scanSummary.techniques, section
                 1.3a.2 holds a sentence that names it in backticks, as `member`
                 or as a dotted path such as `parent.member`, and says
                 "fraction", "exponent", "9007199254740991", "reject" and
                 "SIGNATURE_INVALID". "fraction" also matches "fractional".

The schema's integer type tests the value, so it accepts 1.0 and 1e0 at each of
the members the TBS holds as JSON numbers, and implementations write different
bytes for such a number. One more check holds the text to an outcome for one:

  form           For each of those members, section 1.3a.2 holds a sentence that
                 names it in backticks, as `member` or as a dotted path such as
                 `parent.member`, and says "fraction", "exponent", "reject" and
                 "SIGNATURE_INVALID". "fraction" also matches "fractional", and
                 the name of an object that holds one (`scanSummary`) does not
                 count for it.

With --suite, each jcs-vectors/vectors/*.json of an atx-conformance checkout is
also read: its expected.canonicalHex is decoded and parsed as JSON, and a JSON
number at a member other than those, or one whose absolute value is greater
than 9007199254740991, fails as [vector]. A vector that cannot be read that way
fails as [vector], and so does a checkout with no vectors.

A sentence may wrap across lines but does not cross a blank line, a heading, a
list item or a table cell, and a sentence does not end inside a code span.
Fenced code blocks are not read as sentences. CHANGELOG.md and errata/ are not
checked: they record what earlier text said, and an erratum quotes the published
text verbatim by design. Hidden directories and node_modules are skipped. A file
that is not UTF-8 fails rather than being skipped.

A tree fails with a message that says why when core.md is missing, is not UTF-8
or has no section 1.3a.2 heading, and when the schema is missing, is not JSON or
cannot be walked: a node the walk reaches has a type that is neither a string
nor an array of strings, a oneOf, anyOf or allOf that is not an array, or a
properties that is not an object. The walk reads no other keyword of a node that
has a $ref, so the schema root's own properties, where the included keys are
looked up, is checked apart from it and fails the same way. That message names
the member whose schema holds the node, or the schema root, and the keyword with
its value written as JSON, cut to 60 characters; the value is written only until
60 characters are passed. A schema whose arrays or objects nest deeper than the
json module of the running Python reads is not JSON, and one that nests schemas
deeper than Python's recursion limit lets the walk follow cannot be walked: that
message names the member the walk stopped at, or the schema root, cut to 60
characters. Every other failure is reported with its rule in brackets, as
file:line, or as the file alone for a vector, for the schema and for a file that
is not UTF-8.

    python3 scripts/check_tbs_numbers.py [--root <tree>] [--suite <atx-conformance>]

Exit 0 when every check passes, 1 when one fails, 2 on a usage error.
"""

import argparse
import json
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMA = "schemas/atx-credential-v1.1.schema.json"

# core.md section 1.3a.2 rule 3: the projection writes trustScore as a string.
STRING_ENCODED = {"trustScore"}
NUMERIC = {"integer", "number"}
# RFC 8259 section 6: implementations agree exactly on the value of an integer
# whose absolute value is at most 2^53 - 1.
EXACT = 2**53 - 1
EXACT_RE = re.compile(rf"(?<![0-9]){EXACT}(?![0-9])")
REJECT_RE = re.compile(r"\breject", re.IGNORECASE)
# core.md section 1.3a.2 rules 5 and 6: the projection carries these members into
# the TBS verbatim, whatever they hold, JSON numbers included.
VERBATIM = ("declaredPurpose", "scanSummary.techniques")
VERBATIM_RES = (
    EXACT_RE,
    REJECT_RE,
    re.compile(r"\bfraction", re.IGNORECASE),
    re.compile(r"\bexponent", re.IGNORECASE),
    re.compile(r"\bSIGNATURE_INVALID\b"),
)
# core.md section 1.3a.2 rules 1 and 3: the integer form, decided from the JSON text.
FORM_RES = VERBATIM_RES[1:]

SECTION_RE = re.compile(r"^(#{1,6})\s+1\.3a\.2(?![\w.])")
HEADING_RE = re.compile(r"^(#{1,6})\s")
KEYS_LEAD_RE = re.compile(r"included keys are exactly", re.IGNORECASE)
FENCE_RE = re.compile(r"^\s*(?:```|~~~)")
PARENTHESES_RE = re.compile(r"\([^)]*\)")
NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
MEMBER_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*")

NUMBERS_RE = re.compile(r"\bJSON\s+numbers?\b", re.IGNORECASE)
TBS_RE = re.compile(r"\bTBS\b|\bto-be-signed\b", re.IGNORECASE)
ONLY_RE = re.compile(
    r"\b(?:only|sole|no\s+other)\s+(?:\S+\s+){0,3}?JSON\s+numbers?\b"
    r"|\bJSON\s+numbers?\s+(?:other\s+than|besides|apart\s+from|except)\b",
    re.IGNORECASE,
)

CODE_RE = re.compile(r"`([^`]+)`")
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


def statements(text):
    """(line of "JSON number", [(line, name)]) per sentence that states the only JSON
    numbers in the TBS; the names are the member-shaped code spans in the sentence."""
    out = []
    for first, block in blocks(text.splitlines()):
        for offset, sentence in sentences(block):
            only = ONLY_RE.search(sentence)
            if not only or not TBS_RE.search(sentence):
                continue
            number = NUMBERS_RE.search(sentence, only.start())
            line = first + block.count("\n", 0, offset)
            names = []
            for code in CODE_RE.finditer(sentence):
                name = code.group(1).strip()
                if MEMBER_RE.fullmatch(name):
                    names.append((line + sentence.count("\n", 0, code.start()), name))
            out.append((line + sentence.count("\n", 0, number.start()), names))
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


def node_types(node):
    """The type names a schema node's type gives, as a set (empty when it has no type),
    or None when its type is neither a string nor an array of strings."""
    types = node.get("type", [])
    if isinstance(types, str):
        return {types}
    if isinstance(types, list) and all(isinstance(name, str) for name in types):
        return set(types)
    return None


def cut(text):
    """text cut to 60 characters."""
    return text if len(text) <= 60 else text[:57] + "..."


def shown(value):
    """value written as JSON, cut to 60 characters.

    The value is written a piece at a time, and the writing stops once 60 characters
    are passed. json.dumps writes the whole value, and can raise RecursionError for a
    value json.loads has read: Python 3.14.3 on macOS arm64 reads an array nested
    110,000 deep and cannot write it.
    """
    text = ""
    for chunk in json.JSONEncoder().iterencode(value):
        text += chunk
        if len(text) > 60:
            break
    return cut(text)


def schema_members(schema):
    """({dotted path: set of JSON types}, {dotted path: [schema node]}, [unreadable]) for
    every member the schema defines, at any depth; a member defined in several places has
    a node for each. unreadable says, once per place, where a node the walk reaches has a
    type, oneOf, anyOf, allOf or properties of a JSON type JSON Schema does not allow
    there, and what it holds, or a $ref the walk cannot follow to a schema in this file
    (one that is not a string, is not a "#/" pointer, points at nothing or at a value that
    is not a schema, or leads back to itself), and where the walk stops at Python's
    recursion limit. The walk reads no other keyword of a node that has a $ref,
    so the root's own properties, which main() reads, is checked apart from the walk."""
    found, nodes, unreadable = {}, {}, []
    active = []  # the path of each object node whose walk has not returned

    missing = object()

    def resolve(node, path, seen):
        """The node a chain of $refs leads to, or None when the walk stops there. A $ref
        already followed on the way to this node is recursion and stops the walk without
        a message; a $ref that cannot be followed is reported, naming the member."""
        chain = set()
        while isinstance(node, dict) and "$ref" in node:
            ref = node["$ref"]
            if not isinstance(ref, str):
                wrong(path, "$ref", ref, "a string")
                return None, seen
            if not ref.startswith("#/"):
                wrong(path, "$ref", ref, 'a JSON pointer into this schema ("#/...")')
                return None, seen
            if ref in chain:
                wrong(path, "$ref", ref, "a $ref chain that ends at a schema")
                return None, seen
            if ref in seen:
                return None, seen
            chain.add(ref)
            seen = seen | {ref}
            target = schema
            for part in ref[2:].split("/"):
                target = target.get(part, missing) if isinstance(target, dict) else missing
            if target is missing or not isinstance(target, (dict, bool)):
                wrong(path, "$ref", ref, "a pointer to a schema in this file")
                return None, seen
            node = target
        return node, seen

    def wrong(path, key, value, allowed):
        where = f"`{path}`" if path else "the schema root"
        message = f'{where} has "{key}": {shown(value)}, which is not {allowed}'
        if message not in unreadable:
            unreadable.append(message)

    def walk(node, path, seen):
        node, seen = resolve(node, path, seen)
        if not isinstance(node, dict):
            return
        active.append(path)
        types = node_types(node)
        if types is None:
            wrong(path, "type", node["type"], "a string or an array of strings")
        if path:
            found.setdefault(path, set()).update(types or ())
            nodes.setdefault(path, []).append(node)
        for key in ("oneOf", "anyOf", "allOf"):
            subs = node.get(key, [])
            if not isinstance(subs, list):
                wrong(path, key, subs, "an array")
                continue
            for sub in subs:
                walk(sub, path, seen)
        properties = node.get("properties", {})
        if not isinstance(properties, dict):
            wrong(path, "properties", properties, "an object")
            properties = {}
        for name, sub in properties.items():
            walk(sub, f"{path}.{name}" if path else name, seen)
        for key in ("items", "additionalProperties"):
            if isinstance(node.get(key), dict):
                walk(node[key], path, seen)
        active.pop()

    try:
        walk(schema, "", frozenset())
    except RecursionError as exc:
        # Each schema nested in another is one more call of walk(). active keeps the
        # path of each object node whose walk the error left unfinished, the innermost
        # last.
        path = active[-1] if active else ""
        where = f"`{cut(path)}`" if path else "the schema root"
        unreadable.append(f"{where} nests deeper than the check can walk ({exc})")
    # main() looks the TBS keys up in the root's own properties, which the walk does
    # not read when the root has a $ref.
    if isinstance(schema, dict) and not isinstance(schema.get("properties", {}), dict):
        wrong("", "properties", schema["properties"], "an object")
    return found, nodes, unreadable


def finite(value):
    """value when it is a finite JSON number, else None; a boolean is not a number.

    An int is returned as it is: json reads an integer literal as an exact int, and
    math.isfinite would convert it to a float, which raises OverflowError for an int
    too large to convert, such as 1 followed by 400 zeros.
    """
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    if isinstance(value, int):
        return value
    return value if math.isfinite(value) else None


def integer_bounds(node):
    """(least, greatest) integer a schema node admits by its minimum, exclusiveMinimum,
    maximum and exclusiveMaximum; None on a side that none of them bounds."""
    low, high = [], []
    for key, least in (("minimum", math.ceil), ("exclusiveMinimum", lambda v: math.floor(v) + 1)):
        value = finite(node.get(key))
        if value is not None:
            low.append(least(value))
    for key, greatest in (("maximum", math.floor), ("exclusiveMaximum", lambda v: math.ceil(v) - 1)):
        value = finite(node.get(key))
        if value is not None:
            high.append(greatest(value))
    return (max(low) if low else None), (min(high) if high else None)


def check_bounds(path, nodes):
    """[unbounded] failures for a TBS member the schema types as integer or number."""
    failures = []
    for node in nodes:
        types = node_types(node) or set()
        if not types & NUMERIC:
            continue
        if "number" in types:
            failures.append(
                f"{SCHEMA} [unbounded] types `{path}` as number, which admits a value that is "
                f"not an integer; core.md section 1.3a.2 rule 3 holds only for integers"
            )
            continue
        low, high = integer_bounds(node)
        if low is None or low < -EXACT:
            failures.append(
                f"{SCHEMA} [unbounded] admits an integer below -{EXACT} at `{path}`: it has no "
                f"minimum or exclusiveMinimum at or above that value"
            )
        if high is None or high > EXACT:
            failures.append(
                f"{SCHEMA} [unbounded] admits an integer above {EXACT} at `{path}`: it has no "
                f"maximum or exclusiveMaximum at or below that value"
            )
    return failures


def states_range(lines, start, end):
    """True when a sentence of lines start..end-1 (numbered from 1) says EXACT and "reject"
    and names no member of VERBATIM."""
    for _, block in blocks(lines[start - 1:end - 1]):
        for _, sentence in sentences(block):
            if (EXACT_RE.search(sentence) and REJECT_RE.search(sentence)
                    and not names_verbatim(sentence)):
                return True
    return False


def refers_to(name, path):
    """True when a name in backticks names the member at path: the path itself or its tail."""
    return name == path or path.endswith("." + name)


def names_verbatim(sentence):
    """The members of VERBATIM that a sentence names in backticks."""
    names = [code.group(1).strip() for code in CODE_RE.finditer(sentence)]
    return {path for path in VERBATIM if any(refers_to(name, path) for name in names)}


def verbatim_stated(lines, start, end):
    """The members of VERBATIM named by a sentence of lines start..end-1 (numbered from 1)
    that says each word of VERBATIM_RES."""
    stated = set()
    for _, block in blocks(lines[start - 1:end - 1]):
        for _, sentence in sentences(block):
            if all(word.search(sentence) for word in VERBATIM_RES):
                stated |= names_verbatim(sentence)
    return stated


def form_stated(lines, start, end, numeric):
    """The members of numeric named by a sentence of lines start..end-1 (numbered from 1)
    that says each word of FORM_RES."""
    stated = set()
    for _, block in blocks(lines[start - 1:end - 1]):
        for _, sentence in sentences(block):
            if not all(word.search(sentence) for word in FORM_RES):
                continue
            names = [code.group(1).strip() for code in CODE_RE.finditer(sentence)]
            stated |= {path for path in numeric if any(refers_to(name, path) for name in names)}
    return stated


def json_numbers(node, path=""):
    """(dotted member path, value) per JSON number in node; array positions add nothing."""
    if isinstance(node, bool):
        return
    if isinstance(node, (int, float)):
        yield path, node
    elif isinstance(node, dict):
        for key, value in node.items():
            yield from json_numbers(value, f"{path}.{key}" if path else key)
    elif isinstance(node, list):
        for value in node:
            yield from json_numbers(value, path)


def check_statement(rel, at, spans, numeric, containers, members, tbs_keys):
    """Failures of one statement: `at` is its "JSON number" line, spans its (line, name)s."""
    failures = []
    for path in numeric:
        if not any(refers_to(name, path) for _, name in spans):
            kind = "an integer" if members[path] & NUMERIC == {"integer"} else "a number"
            failures.append(
                f"{rel}:{at} [missing] names the only JSON numbers in the TBS but not "
                f"`{path}`, which the TBS holds as {kind} (the schema types it so)"
            )
    for line, name in spans:
        if any(refers_to(name, path) for path in numeric + containers):
            continue
        matches = [path for path in members if refers_to(name, path)]
        if not matches:
            continue
        if all(path in STRING_ENCODED for path in matches):
            why = "core.md section 1.3a.2 rule 3 makes it a string in the TBS"
        elif all(path.split(".")[0] not in tbs_keys for path in matches):
            why = "the TBS does not include it (core.md section 1.3a.2)"
        else:
            types = sorted(set().union(*(members[path] for path in matches)))
            why = f"the schema types it as {', '.join(types) or 'nothing'}"
        failures.append(
            f"{rel}:{line} [not-a-number] names `{name}` among the only JSON numbers in the "
            f"TBS, but the TBS does not hold it as one: {why}"
        )
    return failures


def check_suite(suite, numeric):
    vectors = sorted((suite / "jcs-vectors" / "vectors").glob("*.json"))
    if not vectors:
        return 0, [f"{suite} [vector] has no jcs-vectors/vectors/*.json; refusing to pass "
                   f"vacuously"]
    failures = []
    for path in vectors:
        rel = path.relative_to(suite).as_posix()
        try:
            doc = json.loads(path.read_text(encoding="utf-8"))
            tbs = json.loads(bytes.fromhex(doc["expected"]["canonicalHex"]).decode("utf-8"))
        except (OSError, ValueError, KeyError, TypeError) as exc:
            failures.append(f"{rel} [vector] cannot read expected.canonicalHex as JSON: {exc}")
            continue
        for member, value in json_numbers(tbs):
            if member not in numeric:
                failures.append(
                    f"{rel} [vector] holds the JSON number {value} at `{member}`, which is "
                    f"not a TBS member the schema types as a number"
                )
            elif abs(value) > EXACT:
                failures.append(
                    f"{rel} [vector] holds the JSON number {value} at `{member}`, whose "
                    f"absolute value is greater than {EXACT}"
                )
    return len(vectors), failures


def main():
    ap = argparse.ArgumentParser(
        description="Assert that a sentence naming the only JSON numbers in the TBS names each "
                    "one, that the schema and core.md bound each to integers of absolute value "
                    "at most 2^53 - 1, and that core.md gives the outcome for a JSON number in a "
                    "member the TBS carries verbatim."
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
    except RecursionError as exc:
        print(f"{SCHEMA} cannot be read as JSON: it nests arrays or objects deeper than the "
              f"json module of this Python can read ({exc})", file=sys.stderr)
        return 1
    members, nodes, unreadable = schema_members(schema)
    if unreadable:
        for problem in unreadable:
            print(f"{SCHEMA} cannot be read as a JSON Schema: {problem}", file=sys.stderr)
        return 1

    failures = []
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
    properties = schema.get("properties", {}) if isinstance(schema, dict) else {}
    tbs_keys = {key for _, key in keys}
    for line, key in keys:
        if key not in properties:
            failures.append(f"core.md:{line} [keys] the TBS key `{key}` is not a property of "
                            f"{SCHEMA}, so its type is unknown")

    numeric = sorted(
        path for path, types in members.items()
        if path.split(".")[0] in tbs_keys and path not in STRING_ENCODED and types & NUMERIC
    )
    containers = sorted({path.rsplit(".", n)[0] for path in numeric
                         for n in range(1, path.count(".") + 1)})
    for path in numeric:
        failures.extend(check_bounds(path, nodes[path]))
    if not states_range(lines, heading, end):
        failures.append(
            f"core.md:{heading} [range] section 1.3a.2 has no sentence that says \"{EXACT}\" and "
            f"\"reject\": rule 3's claim holds only for integers of absolute value at most "
            f"{EXACT}, and the section has to say what a verifier does with one outside it"
        )
    stated_verbatim = verbatim_stated(lines, heading, end)
    for path in VERBATIM:
        if path not in stated_verbatim:
            failures.append(
                f"core.md:{heading} [verbatim] section 1.3a.2 has no sentence that names "
                f"`{path}` and says \"fraction\", \"exponent\", \"{EXACT}\", \"reject\" and "
                f"\"SIGNATURE_INVALID\": the projection carries it into the TBS verbatim, so the "
                f"section has to say what a verifier does with a JSON number in it written with "
                f"a fraction or an exponent part, or of absolute value above {EXACT}"
            )
    stated_form = form_stated(lines, heading, end, numeric)
    for path in numeric:
        if path not in stated_form:
            failures.append(
                f"core.md:{heading} [form] section 1.3a.2 has no sentence that names `{path}` and "
                f"says \"fraction\", \"exponent\", \"reject\" and \"SIGNATURE_INVALID\": the schema's "
                f"integer type tests the value and accepts 1.0 and 1e0, so the section has to say "
                f"what a verifier does with that member written with a fraction or an exponent part"
            )

    files = markdown_files(root)
    stated, in_section = 0, 0
    for path in files:
        rel = path.relative_to(root).as_posix()
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError as exc:
            failures.append(f"{rel} [not-utf-8] {exc.reason}; cannot check it")
            continue
        for at, spans in statements(text):
            stated += 1
            if rel == "core.md" and heading <= at < end:
                in_section += 1
            failures.extend(check_statement(rel, at, spans, numeric, containers, members,
                                            tbs_keys))
    if not in_section:
        failures.append(
            f"core.md:{heading} [absent] section 1.3a.2 has no sentence that names the only "
            f"JSON numbers in the TBS (rule 3 says which ones it holds)"
        )

    vectors = 0
    if suite is not None:
        vectors, vector_failures = check_suite(suite, numeric)
        failures.extend(vector_failures)

    if failures:
        print("a statement of the JSON numbers in the TBS disagrees with what the TBS holds, "
              "or with the range they are bounded to, or gives no outcome for one in a member "
              "the TBS carries verbatim:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    summary = (f"TBS numbers ok: {len(files)} Markdown file(s) read; {stated} sentence(s) name "
               f"the only JSON numbers in the TBS, and each names the {len(numeric)} TBS "
               f"member(s) the schema types as a number ({', '.join(numeric)}); the schema "
               f"bounds each to integers of absolute value at most {EXACT}, and section 1.3a.2 "
               f"says a verifier rejects one outside that range and what it does with a JSON "
               f"number in {' or '.join(VERBATIM)} written with a fraction or an exponent part "
               f"or outside that range, and with each of those members written with a fraction "
               f"or an exponent part")
    if suite is not None:
        summary += (f"; {vectors} jcs-vector(s) hold no JSON number at another member or of "
                    f"absolute value above {EXACT}")
    print(summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
