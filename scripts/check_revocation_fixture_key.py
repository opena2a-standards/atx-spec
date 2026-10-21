#!/usr/bin/env python3
"""Assert that core.md section 12 Coverage names the key the suite's revocation lists use.

core.md section 1.3 step 6 looks a credential's agentDid up in the verifier's
cached revocation list. In atx-conformance at af921e5, the fixtures that give
the verifier a revocation list (verifierState.crl) are in the suite's own
fixture format, whose entries name the revoked agent by agentId, the key step 6
looked up in the core.md revision the fixtures cite, and that format has no
entry member for agentDid. A verifier that looks the agent up by agentDid alone finds no
entry for it there, so the Coverage paragraph of section 12 says which key the
fixtures use. The fixtures live in another repository, so that statement is
checked against a checkout of the suite:

    python3 scripts/check_revocation_fixture_key.py --suite <path-to-atx-conformance> [--root <tree>]

The step 6 key is the first name in backticks of the form agentXxx on the line
that opens step 6 of section 1.3. The keys a fixture uses are the members of
its revocation list entries other than revokedAt and reason. Only the line
that opens with **Coverage.** in section 12 is read, as
scripts/check_coverage_index.py reads it, and it is split into sentences at
a ., ! or ? followed by whitespace. Rules, each failure reported as file:line
with its rule in brackets:

  unnamed  a key some fixture's revocation list uses, other than the step 6
           key, is named in backticks in no sentence of the Coverage
           paragraph that also names the step 6 key in backticks.
  stale    a sentence of the Coverage paragraph that names the step 6 key in
           backticks also names in backticks another agent key, a name of the
           form agentXxx, that no fixture's revocation list uses.
  missing  core.md, the step 6 key, section 12, its Coverage line or a
           fixtures/*.json in the suite is missing, or no fixture gives the
           verifier a revocation list, so a renamed anchor or a wrong --suite
           path cannot pass vacuously.
  fixture  a fixture that cannot be read as JSON, or whose revocation list is
           not an object with an entries array of objects.

--root names the tree whose core.md is read (default: this repository);
scripts/test_revocation_fixture_key.sh uses it on scratch trees. Needs only
python3.

Exit 0 when every rule holds, 1 when one fails, 2 on a usage error.
"""

import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

HOME_FILE = "core.md"
STEPS_HEADING_RE = re.compile(r"^### 1\.3 Local verification algorithm")
ANY_HEADING_RE = re.compile(r"^#+ ")
STEP_6_RE = re.compile(r"^6\.\s")
CONFORMANCE_HEADING_RE = re.compile(r"^## 12\. Conformance")
NEXT_SECTION_RE = re.compile(r"^## ")
ANCHOR_RE = re.compile(r"^\*\*Coverage\.\*\*")
SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+")
NAME_RE = re.compile(r"`([^`\s]+)`")
AGENT_KEY_RE = re.compile(r"agent[A-Z][A-Za-z0-9]*")
ENTRY_FIELDS = {"revokedAt", "reason"}


def step_6_line(lines):
    """(index, text) of the line that opens step 6 of section 1.3, or None."""
    start = next((i for i, line in enumerate(lines) if STEPS_HEADING_RE.match(line)), None)
    if start is None:
        return None
    for i in range(start + 1, len(lines)):
        if ANY_HEADING_RE.match(lines[i]):
            break
        if STEP_6_RE.match(lines[i]):
            return i, lines[i]
    return None


def coverage_line(lines):
    """(index, text) of the Coverage paragraph inside section 12, or None."""
    start = next((i for i, line in enumerate(lines) if CONFORMANCE_HEADING_RE.match(line)), None)
    if start is None:
        return None
    for i in range(start + 1, len(lines)):
        if NEXT_SECTION_RE.match(lines[i]):
            break
        if ANCHOR_RE.match(lines[i]):
            return i, lines[i]
    return None


def list_keys(suite):
    """(keys, failures): each key the suite's revocation list entries name the
    agent by, mapped to the fixtures whose list uses it, and the failures met
    reading the fixtures. keys is None when there is nothing to compare."""
    paths = sorted((suite / "fixtures").glob("*.json"))
    if not paths:
        return None, [f"fixtures [missing] no fixtures/*.json under {suite}"]
    keys = {}
    failures = []
    with_list = 0
    for path in paths:
        rel = f"fixtures/{path.name}"
        try:
            doc = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:  # ValueError: not UTF-8, or not JSON
            failures.append(f"{rel} [fixture] cannot be read as JSON: {exc}")
            continue
        state = doc.get("verifierState") if isinstance(doc, dict) else None
        crl = state.get("crl") if isinstance(state, dict) else None
        if crl is None:
            continue
        entries = crl.get("entries") if isinstance(crl, dict) else None
        if not isinstance(entries, list) or not all(isinstance(e, dict) for e in entries):
            failures.append(
                f"{rel} [fixture] verifierState.crl is not an object with an entries array of objects"
            )
            continue
        with_list += 1
        for entry in entries:
            for key in sorted(set(entry) - ENTRY_FIELDS):
                users = keys.setdefault(key, [])
                if path.stem not in users:
                    users.append(path.stem)
    if not with_list:
        failures.append(
            f"fixtures [missing] no fixture under {suite} gives the verifier a revocation list "
            f"(verifierState.crl)"
        )
        return None, failures
    return keys, failures


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
    lines = text.splitlines()

    found = step_6_line(lines)
    if found is None:
        return [f"{HOME_FILE} [missing] no line opening step 6 (\"6. \") in section 1.3, "
                f"Local verification algorithm"]
    step_key = next((n for n in NAME_RE.findall(found[1]) if AGENT_KEY_RE.fullmatch(n)), None)
    if step_key is None:
        return [f"{HOME_FILE}:{found[0] + 1} [missing] step 6 of section 1.3 names no agent key "
                f"in backticks (`agentDid`)"]

    found = coverage_line(lines)
    if found is None:
        return [f"{HOME_FILE} [missing] no line opening with **Coverage.** in section 12, Conformance"]
    index, para = found
    where = f"{HOME_FILE}:{index + 1}"

    keys, failures = list_keys(suite)
    if keys is None:
        return failures

    beside = [names for names in (set(NAME_RE.findall(s)) for s in SENTENCE_SPLIT_RE.split(para))
              if step_key in names]
    for key in sorted(set(keys) - {step_key}):
        if any(key in names for names in beside):
            continue
        users = ", ".join(f"fixtures/{name}.json" for name in keys[key])
        failures.append(
            f"{where} [unnamed] the revocation list of {users} names the revoked agent by `{key}`, "
            f"where section 1.3 step 6 looks up `{step_key}`; no sentence of the Coverage paragraph "
            f"names both"
        )
    stale = {name for names in beside for name in names if AGENT_KEY_RE.fullmatch(name)}
    for name in sorted(stale - set(keys) - {step_key}):
        failures.append(
            f"{where} [stale] a sentence of the Coverage paragraph names `{name}` beside "
            f"`{step_key}`; no fixture's revocation list names the revoked agent by `{name}`"
        )
    return failures


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--suite", required=True, help="path to a checkout of opena2a-standards/atx-conformance")
    ap.add_argument("--root", default=str(ROOT), help="tree to check (default: this repository)")
    args = ap.parse_args()

    failures = check(pathlib.Path(args.root).resolve(), pathlib.Path(args.suite).resolve())
    if failures:
        print("core.md section 12 Coverage and the key the suite's revocation lists use disagree:\n",
              file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        print(
            "\nName each key the fixtures' revocation lists use in a sentence of the Coverage "
            "paragraph that names the key section 1.3 step 6 looks up, and drop a key no "
            "fixture's list uses.",
            file=sys.stderr,
        )
        return 1

    print("revocation fixture key ok: each key the suite's revocation lists use is the key "
          "section 1.3 step 6 looks up or is named beside it in the Coverage paragraph")
    return 0


if __name__ == "__main__":
    sys.exit(main())
