#!/usr/bin/env python3
"""Assert that core.md section 12 says which conformance fixtures the credential schema refuses.

schemas/atx-credential-v1.1.schema.json refuses an atcVersion 1.1 credential
whose signatures lack an Ed25519 or an ML-DSA-65 entry (core.md section 1.1).
The atx-conformance fixtures pin signing bytes and verdicts rather than
issuance policy, so some of them carry one suite only, and the Issuer paragraph
of core.md section 12 says which of them the schema refuses. The fixtures live
in another repository, so that statement drifts: it said "those of them that
declare atcVersion 1.1" after a clause about the fixtures that carry Ed25519
signatures only, while two fixtures that declare 1.1 carry both suites and
validate, and it did not name v1_1-hybrid-pq-only, which carries an ML-DSA-65
signature and no Ed25519 one.

This check validates the atx member of every fixture in the suite's fixtures/
directory against the schema, and reads the sentences of the section 12 line
that opens with **Issuer.** that say the schema refuses ("schema refuses",
"refused by the schema", "refused by the credential schema"):

  unaccounted  every fixture the schema refuses on its signatures member is
               accounted for in those sentences. A fixture that declares
               atcVersion 1.1 and carries Ed25519 signatures only is accounted
               for by the phrase "Ed25519-only fixtures that declare
               `atcVersion` 1.1"; any other is named in backticks.
  stale        those sentences describe only refusals the suite has: the
               phrase stands only while a fixture that declares 1.1 and
               carries Ed25519 signatures only is refused, and every other
               name they give in backticks, with or without .json, is read
               as a fixture name, so the suite ships that fixture and the
               schema refuses it on its signatures member. A fixture the
               suite removed or renamed fails, and so does a member name
               such as `signatures` in backticks outside the phrase. A
               fixture that cannot be validated against the schema (see
               fixture) is left out of this rule, as whether the schema
               refuses it is not known.
  missing      core.md, its section 12 Issuer line, the schema or a
               fixtures/*.json in the suite is missing, so a renamed anchor or
               a wrong --suite path cannot pass vacuously. A schema that cannot
               be read as JSON fails the same way, and so does one the JSON
               Schema 2020-12 metaschema refuses, such as one with a type,
               oneOf or properties of the wrong JSON type. Its failure line
               gives the first place the metaschema reports, as a JSON path,
               and the metaschema's message for it; where that message opens
               with the value in Python notation, the value is written as JSON,
               cut to 60 characters. A schema whose arrays or objects nest
               deeper than the json module of the running Python reads fails
               the same way, and so does one that nests deeper than the check
               can follow when it compares it with the metaschema, within
               Python's recursion limit; that line gives the schema's deepest
               place as a JSON path, cut to 60 characters. The metaschema does
               not follow a $ref, so a schema with a $ref or $dynamicRef that
               does not resolve fails the same way once a fixture's validation
               reaches it: a JSON pointer that names nothing in the schema,
               such as #/$defs/nonexistent or #/allOf/x, an anchor no subschema
               declares, or a document jsonschema cannot retrieve. Its failure
               line names that fixture and gives the $ref or $dynamicRef whose
               lookup failed, as a JSON path, with its value written as JSON:
               the check's validator looks a $ref or $dynamicRef up before
               jsonschema's code for it does. A reference to a document
               jsonschema cannot retrieve is given by its value alone, and so
               is one jsonschema looks up itself, as it does for
               unevaluatedItems and unevaluatedProperties and in a subschema
               that declares the $schema of another dialect. An error
               jsonschema raises for another cause, such as the ValueError for
               a NaN fixture member under a multipleOf of 0.5, stops the check
               as it is.
  fixture      a fixture that cannot be read as JSON, nests arrays or objects
               deeper than the json module of the running Python reads, has no
               object atx member, or cannot be validated against the schema
               because the validation goes deeper than Python's recursion
               limit lets the check follow, as a long chain of $ref the
               fixture reaches does.

Each failure is reported as file:line with its rule in brackets.

    python3 scripts/check_schema_refusals.py --suite <path-to-atx-conformance> [--root <tree>]

--root names the tree whose core.md and schema are read (default: this
repository); scripts/test_schema_refusals.sh uses it on scratch trees. Needs
python3 and the jsonschema package, as scripts/validate_examples.py does.

Exit 0 when the Issuer paragraph accounts for every refusal and describes no
other, 1 otherwise, 2 on a usage error or when jsonschema is not installed.
"""

import argparse
import contextlib
import json
import pathlib
import re
import sys
import traceback

try:
    from jsonschema import Draft202012Validator, SchemaError
    from jsonschema.validators import create, validates
    from referencing import Registry
    from referencing.exceptions import Unresolvable
except ImportError:
    print("error: the 'jsonschema' package is required (pip install jsonschema)", file=sys.stderr)
    sys.exit(2)

ROOT = pathlib.Path(__file__).resolve().parent.parent

HOME_FILE = "core.md"
SCHEMA_FILE = "schemas/atx-credential-v1.1.schema.json"
HEADING_RE = re.compile(r"^## 12\. Conformance")
NEXT_HEADING_RE = re.compile(r"^## ")
ANCHOR_RE = re.compile(r"^\*\*Issuer\.\*\*")
SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+")
REFUSES_RE = re.compile(
    r"\bschema\s+refuses\b|\brefused\s+by\s+the\s+(?:credential\s+)?schema\b", re.IGNORECASE
)
ED25519_ONLY_RE = re.compile(
    r"\bEd25519-only\s+fixtures\s+that\s+declare\s+`atcVersion`\s+1\.1\b", re.IGNORECASE
)
NAME_RE = re.compile(r"`([^`\s]+)`")
PHRASE = "Ed25519-only fixtures that declare `atcVersion` 1.1"
REFERENCE_KEYWORDS = ("$ref", "$dynamicRef")
UNEVALUATED_KEYWORDS = ("unevaluatedItems", "unevaluatedProperties")
DIALECT = "draft2020-12"  # the name jsonschema registers Draft202012Validator under
# The code of the method of the referencing library that looks a reference up, lookup(ref).
LOOKUP_CODE = type(Registry().resolver()).lookup.__code__


def issuer_line(lines):
    """(index, text) of the Issuer paragraph inside section 12, or None."""
    start = next((i for i, line in enumerate(lines) if HEADING_RE.match(line)), None)
    if start is None:
        return None
    for i in range(start + 1, len(lines)):
        if NEXT_HEADING_RE.match(lines[i]):
            break
        if ANCHOR_RE.match(lines[i]):
            return i, lines[i]
    return None


def algorithms(atx):
    """The signature algorithms an atx member declares, each once, in order."""
    found = []
    entries = atx.get("signatures")
    for entry in entries if isinstance(entries, list) else []:
        alg = entry.get("algorithm") if isinstance(entry, dict) else None
        if isinstance(alg, str) and alg not in found:
            found.append(alg)
    return found


def refused_on_signatures(validator, atx):
    """True when the schema reports an error at the atx member's signatures."""
    return any(list(error.absolute_path)[:1] == ["signatures"] for error in validator.iter_errors(atx))


def cut(text):
    """text cut to 60 characters."""
    return text if len(text) <= 60 else text[:57] + "..."


def shown(value):
    """value written as JSON, cut to 60 characters."""
    return cut(json.dumps(value))


def deepest_place(value):
    """The JSON path of the most deeply nested array or object in value, cut to 60
    characters. The walk keeps its own stack, so it does not stop at Python's recursion
    limit on a value nested deeper than that."""
    parents = [None]  # (index of the parent in parents, key) for each array or object
    stack = [(value, 0, 0)]  # (array or object, depth, its index in parents)
    deepest, deepest_depth = 0, 0
    while stack:
        node, depth, index = stack.pop()
        if depth > deepest_depth:
            deepest, deepest_depth = index, depth
        members = (node.items() if isinstance(node, dict)
                   else enumerate(node) if isinstance(node, list) else ())
        for key, child in members:
            if isinstance(child, (dict, list)):
                parents.append((index, key))
                stack.append((child, depth + 1, len(parents) - 1))
    keys = []
    while parents[deepest] is not None:
        deepest, key = parents[deepest]
        keys.append(f"[{key}]" if isinstance(key, int) else f".{key}")
    return cut("$" + "".join(reversed(keys)))


def schema_problem(error):
    """What a SchemaError says, for its failure line: the place in the schema as a JSON path,
    then the metaschema's message for it. Where that message opens with the value in Python
    notation, the value is written as JSON instead, cut to 60 characters."""
    message, value = error.message, repr(error.instance)
    if message.startswith(value):
        message = shown(error.instance) + message[len(value):]
    return f"{error.json_path}: {message}"


class UnresolvedReference(Exception):
    """Raised by a $ref or $dynamicRef of the validator watched_validator() returns when its
    own lookup fails; args are the keyword, the subschema that holds it and the error the
    lookup raised."""


def watched_validator(schema):
    """A JSON Schema 2020-12 validator for schema whose $ref and $dynamicRef look their
    reference up before jsonschema's code for them does, and raise UnresolvedReference when
    that lookup fails. Every other error jsonschema raises passes as it is, the errors raised
    in the subschema a reference resolves to included.

    jsonschema's unevaluatedItems and unevaluatedProperties look a $ref or $dynamicRef beside
    them up themselves. The validator evaluates them after the other keywords of their
    subschema, so that reference is looked up by its own keyword first. jsonschema validates a
    subschema that declares $schema with the validator registered for that dialect; see
    registered()."""
    def looked_up_first(keyword, function):
        def reference_keyword(validator, value, instance, subschema):
            # jsonschema's code for $ref and $dynamicRef looks the reference up with this
            # resolver, the one in effect where the keyword is, and then validates the
            # instance against what it resolves to.
            resolver = getattr(validator, "_resolver", None)
            if resolver is not None:
                try:
                    resolver.lookup(value)
                # A pointer that steps into a number, a boolean or null, or that indexes an
                # array or a string with a segment that is not a number, raises TypeError or
                # ValueError, and so does a value urllib cannot parse, such as http://[bad.
                except (Unresolvable, TypeError, ValueError) as exc:
                    raise UnresolvedReference(keyword, subschema, exc) from exc
            yield from function(validator, value, instance, subschema)
        return reference_keyword

    validators = dict(Draft202012Validator.VALIDATORS)
    for keyword in REFERENCE_KEYWORDS:
        validators[keyword] = looked_up_first(keyword, validators[keyword])
    validator_class = create(
        meta_schema=Draft202012Validator.META_SCHEMA,
        validators=validators,
        type_checker=Draft202012Validator.TYPE_CHECKER,
        format_checker=Draft202012Validator.FORMAT_CHECKER,
        id_of=Draft202012Validator.ID_OF,
        applicable_validators=lambda subschema: sorted(
            subschema.items(), key=lambda item: item[0] in UNEVALUATED_KEYWORDS),
    )
    return validator_class(schema)


@contextlib.contextmanager
def registered(validator_class):
    """validator_class registered for the JSON Schema 2020-12 dialect while the block runs, and
    Draft202012Validator again after it. jsonschema validates a subschema that declares a
    $schema with the validator registered for it, as it does the schema root where a $ref of #
    leads back to it; a subschema that declares another dialect is validated by jsonschema's
    own validator for that dialect."""
    validates(DIALECT)(validator_class)
    try:
        yield
    finally:
        validates(DIALECT)(Draft202012Validator)


def place_of(schema, subschema):
    """The keys that lead from the schema root to subschema, or None when the schema does not
    hold it. The walk keeps its own stack, as deepest_place() does, so a value nested deeper
    than Python's recursion limit does not stop it."""
    parents = [None]  # (index of the parent in parents, key) for each array or object
    stack = [(schema, 0)]  # (array or object, its index in parents)
    while stack:
        node, index = stack.pop()
        if node is subschema:
            keys = []
            while parents[index] is not None:
                index, key = parents[index]
                keys.append(key)
            return tuple(reversed(keys))
        members = (node.items() if isinstance(node, dict)
                   else enumerate(node) if isinstance(node, list) else ())
        for key, child in members:
            if isinstance(child, (dict, list)):
                parents.append((index, key))
                stack.append((child, len(parents) - 1))
    return None


def unresolved(schema, keyword, subschema, error):
    """What the failure line says about the $ref or $dynamicRef keyword of subschema, whose
    lookup raised error: its place, as jsonschema writes the place of a SchemaError, and its
    value written as JSON. A reference to a document jsonschema cannot retrieve is given by
    its value alone."""
    # referencing raises Unresolvable itself for a document it cannot retrieve, and a subclass
    # of it for a pointer or an anchor that names nothing in one it holds.
    value = f"{shown(subschema[keyword])} does not resolve"
    place = None if type(error) is Unresolvable else place_of(schema, subschema)
    if place is None:
        return value
    return f"{SchemaError('', path=place + (keyword,)).json_path}: {value}"


def looked_up(exc):
    """The reference jsonschema gave the lookup of the referencing library that raised exc, or
    that raised the error jsonschema raised exc from; None when no lookup raised it.
    jsonschema makes lookups of its own, not through the validator's $ref or $dynamicRef: for
    unevaluatedItems and unevaluatedProperties, and in a subschema that declares the $schema
    of another dialect."""
    for error in (exc, exc.__cause__):
        # A traceback runs from the outermost call to the innermost, so the first lookup in
        # it is the one jsonschema called.
        for frame, _ in traceback.walk_tb(getattr(error, "__traceback__", None)):
            if frame.f_code is LOOKUP_CODE:
                return frame.f_locals.get("ref")
    return None


def check(root, suite):
    home = root / HOME_FILE
    try:
        text = home.read_text(encoding="utf-8")
    except FileNotFoundError:
        return [f"{HOME_FILE} [missing] file not found"]
    except UnicodeDecodeError as exc:
        return [f"{HOME_FILE} [missing] not UTF-8 ({exc.reason}); cannot be read"]
    except OSError as exc:
        return [f"{HOME_FILE} [missing] cannot be read: {exc}"]
    found = issuer_line(text.splitlines())
    if found is None:
        return [f"{HOME_FILE} [missing] no line opening with **Issuer.** in section 12, Conformance"]
    index, para = found
    where = f"{HOME_FILE}:{index + 1}"

    try:
        schema = json.loads((root / SCHEMA_FILE).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        return [f"{SCHEMA_FILE} [missing] cannot be read as JSON: {exc}"]
    except RecursionError as exc:
        return [f"{SCHEMA_FILE} [missing] cannot be read as JSON: it nests arrays or objects "
                f"deeper than the json module of this Python can read ({exc})"]
    # iter_errors() stops with a TypeError on a oneOf or a type of 5, and with an
    # AttributeError on a properties of 5; the metaschema refuses each of them.
    try:
        Draft202012Validator.check_schema(schema)
    except SchemaError as exc:
        return [f"{SCHEMA_FILE} [missing] cannot be read as a JSON Schema: {schema_problem(exc)}"]
    except RecursionError as exc:
        # check_schema() walks every subschema, whether a fixture reaches it or not.
        return [f"{SCHEMA_FILE} [missing] cannot be read as a JSON Schema: it nests deeper than "
                f"the check can follow when it compares it with the JSON Schema 2020-12 "
                f"metaschema; its deepest place is {deepest_place(schema)} ({exc})"]
    validator = watched_validator(schema)

    paths = sorted((suite / "fixtures").glob("*.json"))
    if not paths:
        return [f"fixtures [missing] no fixtures/*.json under {suite}"]

    failures = []
    refused = {}  # fixture name -> (atcVersion, algorithms)
    unvalidated = {}  # the same, for a fixture the check could not validate
    for path in paths:
        rel = f"fixtures/{path.name}"
        try:
            doc = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:  # ValueError: not UTF-8, or not JSON
            failures.append(f"{rel} [fixture] cannot be read as JSON: {exc}")
            continue
        except RecursionError as exc:
            failures.append(f"{rel} [fixture] cannot be read as JSON: it nests arrays or objects "
                            f"deeper than the json module of this Python can read ({exc})")
            continue
        atx = doc.get("atx") if isinstance(doc, dict) else None
        if not isinstance(atx, dict):
            failures.append(f"{rel} [fixture] has no object atx member to validate")
            continue
        # The metaschema does not follow a $ref, so one that does not resolve passes it,
        # and iter_errors() raises once the validation of a fixture reaches it.
        try:
            with registered(type(validator)):
                is_refused = refused_on_signatures(validator, atx)
        except RecursionError as exc:  # as a long chain of $ref the fixture reaches can raise
            failures.append(f"{rel} [fixture] cannot be validated against the schema: the "
                            f"validation goes deeper than the check can follow ({exc})")
            unvalidated[path.stem] = (atx.get("atcVersion"), algorithms(atx))
            continue
        except UnresolvedReference as exc:
            return [f"{SCHEMA_FILE} [missing] cannot validate {rel}: "
                    f"{unresolved(schema, *exc.args)}"]
        except (Unresolvable, TypeError, ValueError) as exc:
            ref = looked_up(exc)
            if ref is None:  # raised for another cause, such as NaN under a multipleOf of 0.5
                raise
            return [f"{SCHEMA_FILE} [missing] cannot validate {rel}: {shown(ref)} does not resolve"]
        if is_refused:
            refused[path.stem] = (atx.get("atcVersion"), algorithms(atx))

    claims = [s for s in SENTENCE_SPLIT_RE.split(para) if REFUSES_RE.search(s)]
    has_phrase = any(ED25519_ONLY_RE.search(s) for s in claims)
    # The phrase's `atcVersion` is a member name; every other name in backticks is a fixture name.
    named = {n[: -len(".json")] if n.endswith(".json") else n
             for s in claims for n in NAME_RE.findall(ED25519_ONLY_RE.sub(" ", s))}
    ed25519_only = {name for name, (version, algs) in refused.items()
                    if version == "1.1" and algs == ["Ed25519"]}
    # Whether the schema refuses a fixture it could not be validated against is not known,
    # so the stale rules below say nothing about one.
    unvalidated_ed25519_only = {name for name, (version, algs) in unvalidated.items()
                                if version == "1.1" and algs == ["Ed25519"]}

    for name in sorted(refused):
        if name in named or (has_phrase and name in ed25519_only):
            continue
        version, algs = refused[name]
        how = (f'names it or says "{PHRASE}"' if name in ed25519_only else "names it")
        failures.append(
            f"{where} [unaccounted] the schema refuses fixtures/{name}.json on its signatures "
            f"member (atcVersion {version}, signatures: {', '.join(algs) or 'none'}); no sentence "
            f"of the Issuer paragraph that says the schema refuses {how}"
        )
    if has_phrase and not ed25519_only and not unvalidated_ed25519_only:
        failures.append(
            f'{where} [stale] the Issuer paragraph says the schema refuses the "{PHRASE}"; '
            f"no fixture in the suite declares atcVersion 1.1, carries Ed25519 signatures only "
            f"and is refused"
        )
    fixture_names = {path.stem for path in paths}
    for name in sorted((named & fixture_names) - set(refused) - set(unvalidated)):
        failures.append(
            f"{where} [stale] the Issuer paragraph says the schema refuses fixtures/{name}.json; "
            f"the schema does not refuse it on its signatures member"
        )
    for name in sorted(named - fixture_names):
        failures.append(
            f"{where} [stale] the Issuer paragraph says the schema refuses fixtures/{name}.json; "
            f"the suite ships no such fixture (a name in backticks in a sentence that says the "
            f"schema refuses is read as a fixture name)"
        )
    return failures


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--suite", required=True, help="path to a checkout of opena2a-standards/atx-conformance")
    ap.add_argument("--root", default=str(ROOT), help="tree to check (default: this repository)")
    args = ap.parse_args()

    failures = check(pathlib.Path(args.root).resolve(), pathlib.Path(args.suite).resolve())
    if failures:
        print("core.md section 12 and the fixtures the credential schema refuses disagree:\n",
              file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        print(
            "\nSay in the Issuer paragraph of section 12 which fixtures the schema refuses, and "
            "drop what it says about a refusal the suite no longer has.",
            file=sys.stderr,
        )
        return 1

    print("schema refusals ok: the Issuer paragraph accounts for every fixture the schema "
          "refuses on its signatures member and names no other")
    return 0


if __name__ == "__main__":
    sys.exit(main())
