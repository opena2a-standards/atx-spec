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
               such as `signatures` in backticks outside the phrase.
  missing      core.md, its section 12 Issuer line, the schema or a
               fixtures/*.json in the suite is missing, so a renamed anchor or
               a wrong --suite path cannot pass vacuously. A schema that cannot
               be read as JSON fails the same way, and so does one the JSON
               Schema 2020-12 metaschema refuses, such as one with a type,
               oneOf or properties of the wrong JSON type. Its failure line
               gives the first place the metaschema reports, as a JSON path,
               and the metaschema's message for it; where that message opens
               with the value in Python notation, the value is written as JSON,
               cut to 60 characters.
  fixture      a fixture that cannot be read as JSON, or has no object atx
               member.

Each failure is reported as file:line with its rule in brackets.

    python3 scripts/check_schema_refusals.py --suite <path-to-atx-conformance> [--root <tree>]

--root names the tree whose core.md and schema are read (default: this
repository); scripts/test_schema_refusals.sh uses it on scratch trees. Needs
python3 and the jsonschema package, as scripts/validate_examples.py does.

Exit 0 when the Issuer paragraph accounts for every refusal and describes no
other, 1 otherwise, 2 on a usage error or when jsonschema is not installed.
"""

import argparse
import json
import pathlib
import re
import sys

try:
    from jsonschema import Draft202012Validator, SchemaError
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


def shown(value):
    """value written as JSON, cut to 60 characters."""
    text = json.dumps(value)
    return text if len(text) <= 60 else text[:57] + "..."


def schema_problem(error):
    """What a SchemaError says, for its failure line: the place in the schema as a JSON path,
    then the metaschema's message for it. Where that message opens with the value in Python
    notation, the value is written as JSON instead, cut to 60 characters."""
    message, value = error.message, repr(error.instance)
    if message.startswith(value):
        message = shown(error.instance) + message[len(value):]
    return f"{error.json_path}: {message}"


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
    # iter_errors() stops with a TypeError on a oneOf or a type of 5, and with an
    # AttributeError on a properties of 5; the metaschema refuses each of them.
    try:
        Draft202012Validator.check_schema(schema)
    except SchemaError as exc:
        return [f"{SCHEMA_FILE} [missing] cannot be read as a JSON Schema: {schema_problem(exc)}"]
    validator = Draft202012Validator(schema)

    paths = sorted((suite / "fixtures").glob("*.json"))
    if not paths:
        return [f"fixtures [missing] no fixtures/*.json under {suite}"]

    failures = []
    refused = {}  # fixture name -> (atcVersion, algorithms)
    for path in paths:
        rel = f"fixtures/{path.name}"
        try:
            doc = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:  # ValueError: not UTF-8, or not JSON
            failures.append(f"{rel} [fixture] cannot be read as JSON: {exc}")
            continue
        atx = doc.get("atx") if isinstance(doc, dict) else None
        if not isinstance(atx, dict):
            failures.append(f"{rel} [fixture] has no object atx member to validate")
            continue
        if refused_on_signatures(validator, atx):
            refused[path.stem] = (atx.get("atcVersion"), algorithms(atx))

    claims = [s for s in SENTENCE_SPLIT_RE.split(para) if REFUSES_RE.search(s)]
    has_phrase = any(ED25519_ONLY_RE.search(s) for s in claims)
    # The phrase's `atcVersion` is a member name; every other name in backticks is a fixture name.
    named = {n[: -len(".json")] if n.endswith(".json") else n
             for s in claims for n in NAME_RE.findall(ED25519_ONLY_RE.sub(" ", s))}
    ed25519_only = {name for name, (version, algs) in refused.items()
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
    if has_phrase and not ed25519_only:
        failures.append(
            f'{where} [stale] the Issuer paragraph says the schema refuses the "{PHRASE}"; '
            f"no fixture in the suite declares atcVersion 1.1, carries Ed25519 signatures only "
            f"and is refused"
        )
    fixture_names = {path.stem for path in paths}
    for name in sorted((named & fixture_names) - set(refused)):
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
