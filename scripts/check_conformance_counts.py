#!/usr/bin/env python3
"""Assert the conformance-suite fixture counts stated here match the suite.

README.md, docs/conformance.md and core.md (section 12) each state how many
fixtures the atx-conformance suite ships, docs/conformance.md restates the
pass count the reference verifiers report, and the reference verifier's
summary line in README.md states its pass and fail counts. Those are
measurements taken in another repository, so they are checked here rather than
maintained by hand: the count drifted to 18 while the suite shipped 20 and
nothing caught it. A stated pass count must equal the number of fixtures and a
stated fail count must be 0.

core.md section 12 also names the fixtures no conforming verifier produces the
pinned verdict for, and those are checked against the suite the same way. The
required-suites rule of section 1.3 step 5 rejects an atcVersion 1.1 credential
that declares no ML-DSA-65 entry, so a fixture that pins ACCEPT on one is
excepted from the pinned-verdict requirement: the Coverage paragraph names each
such fixture and the Conformance suite paragraph states their number. The
Coverage paragraph named four of them while the suite shipped five. The check
reads each fixture's atx.atcVersion, the algorithm of each atx.signatures entry
and expected.verifyResult, and fails unless:

  - each fixture that pins ACCEPT on an atcVersion 1.1 credential that declares
    no ML-DSA-65 entry is named in backticks in a sentence of the section 12
    line opening with **Coverage.** that names the required-suites rule or says
    "excepts";
  - each name in backticks in those sentences, with or without .json, is such a
    fixture the suite ships. A name that holds an uppercase letter, as a member
    name (atcVersion) or a rejection category (SIGNATURE_INVALID) does, is not
    read as a fixture name;
  - each number of them stated in those sentences, or in a sentence of the
    section 12 line opening with **Conformance suite.** that says "excepts",
    equals the number of such fixtures the suite ships. A number is a word from
    zero to twenty, or a numeral, after "the" ("other than the five that", "each
    of the five"), or a word from zero to twenty before "fixtures" ("Five
    fixtures");
  - while the suite ships such a fixture, a sentence of the Conformance suite
    paragraph says "excepts".

A fixture that cannot be read as JSON fails, as whether it is one of them is not
known.

This repository does not contain the fixtures, so the suite is supplied by the
caller:

    python3 scripts/check_conformance_counts.py --suite <path-to-atx-conformance> [--root <tree>]

--root names the tree whose README.md, docs/conformance.md and core.md are read
(default: this repository); scripts/test_conformance_counts.sh uses it on
scratch trees.

CI checks out opena2a-standards/atx-conformance at main and passes it here. The
ref is deliberately main and not a pinned SHA: the drift being caught is exactly
"the suite moved and the spec did not", and a pinned ref would reproduce the bug.

Exit 0 when every stated count and excepted fixture matches the suite, 1
otherwise.
"""

import argparse
import bisect
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Files that state a fixture count, and a human pointer to where.
CLAIM_FILES = {
    "README.md": "the reference verifier's summary line under the first use case",
    "docs/conformance.md": "the conformance-suite paragraph",
    "core.md": "section 12, Conformance",
}


# A word that may sit between the count and "fixtures" and still describe the
# whole suite. A count with any other word there ("three hybrid fixtures") is a
# subset of the suite, so it is not compared with the suite's size.
WHOLE_SUITE_QUALIFIERS = ("byte-pinned", "pinned", "shipped", "conformance")

FIXTURES_RE = re.compile(
    r"\b(\d+)\s+(?:(?:" + "|".join(map(re.escape, WHOLE_SUITE_QUALIFIERS)) + r")\s+)?fixtures\b"
)
OF_PASS_RE = re.compile(r"\b(\d+)\s+of\s+(\d+)\s+PASS\b")
SUMMARY_RE = re.compile(r"\b(\d+)\s+pass,\s+(\d+)\s+fail\b")
NEWLINE_RE = re.compile(r"\n")

# The fixtures the pinned-verdict requirement of core.md section 12 excepts: each
# pins ACCEPT on an atcVersion 1.1 credential that declares no ML-DSA-65 entry,
# which the required-suites rule of section 1.3 step 5 rejects.
EXCEPT_FILE = "core.md"
SECTION_RE = re.compile(r"^## 12\. Conformance")
NEXT_SECTION_RE = re.compile(r"^## ")
SUITE_ANCHOR = "**Conformance suite.**"
COVERAGE_ANCHOR = "**Coverage.**"
SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+")
EXCEPTS_RE = re.compile(r"\bexcepts\b")
RULE_RE = re.compile(r"\brequired-suites rule\b")
NAME_RE = re.compile(r"`([^`\s]+)`")
UPPERCASE_RE = re.compile(r"[A-Z]")
NUMBER_WORDS = (
    "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
    "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
    "nineteen", "twenty",
)
# "other than the five that", "each of the five", "Five fixtures". A numeral is read
# after "the" only: before "fixtures" it is a count of the whole suite (FIXTURES_RE),
# and one followed by a fraction ("the 1.1 form") is not a count.
EXCEPTED_COUNT_RE = re.compile(
    r"\bthe\s+(" + "|".join(NUMBER_WORDS) + r"|\d+(?!\d|\.\d))\b"
    r"|\b(" + "|".join(NUMBER_WORDS) + r")\s+fixtures\b",
    re.IGNORECASE,
)
KIND = "pins ACCEPT on an atcVersion 1.1 credential that declares no ML-DSA-65 entry"
KIND_PLURAL = "pin ACCEPT on an atcVersion 1.1 credential that declares no ML-DSA-65 entry"
RULE = "the required-suites rule of section 1.3 step 5"


def line_of(newlines, offset):
    """The line offset sits on, found by bisecting where each newline of its
    text stands. Counting newlines from the start of the file for each stale
    count took time quadratic in the number of stale counts."""
    return bisect.bisect_left(newlines, offset) + 1


def stated_counts(text):
    """Every fixture/pass/fail count asserted in one document.

    Matches the phrasings actually used:
      "The suite ships 18 fixtures"
      "ships 18 byte-pinned fixtures"
      "18 fixtures (baseline, hybrid, ...)"
      "Both verifiers report 18 of 18 PASS"
      "# summary: 18 pass, 0 fail (18 fixtures)"  (the Go reference verifier's last line)
    """
    found = []
    for m in FIXTURES_RE.finditer(text):
        found.append(("fixtures", int(m.group(1)), m.start()))
    for m in OF_PASS_RE.finditer(text):
        found.append(("pass", int(m.group(1)), m.start()))
        found.append(("of", int(m.group(2)), m.start()))
    for m in SUMMARY_RE.finditer(text):
        found.append(("pass", int(m.group(1)), m.start()))
        found.append(("fail", int(m.group(2)), m.start()))
    return found


def section_12_line(lines, anchor):
    """(index, where) of the line inside core.md section 12 that opens with anchor;
    the index is None when there is no such line, and where says why."""
    start = next((i for i, line in enumerate(lines) if SECTION_RE.match(line)), None)
    if start is None:
        return None, f"{EXCEPT_FILE} (it has no ## 12. Conformance heading)"
    for i in range(start + 1, len(lines)):
        if NEXT_SECTION_RE.match(lines[i]):
            break
        if lines[i].startswith(anchor):
            return i, f"{EXCEPT_FILE}:{i + 1}"
    return None, f"{EXCEPT_FILE} (section 12 has no line opening with {anchor})"


def sentences_saying(lines, index, *patterns):
    """The sentences of lines[index] that match one of patterns; none when index is None."""
    if index is None:
        return []
    return [s for s in SENTENCE_SPLIT_RE.split(lines[index]) if any(p.search(s) for p in patterns)]


def excepted_counts(sentences):
    """(number, the words that state it) for each number of excepted fixtures the
    sentences state."""
    counts = []
    for sentence in sentences:
        for m in EXCEPTED_COUNT_RE.finditer(sentence):
            word = (m.group(1) or m.group(2)).lower()
            counts.append((int(word) if word.isdigit() else NUMBER_WORDS.index(word), m.group(0)))
    return counts


def algorithms(atx):
    """The signature algorithms an atx member declares, each once, in order."""
    found = []
    entries = atx.get("signatures")
    for entry in entries if isinstance(entries, list) else []:
        alg = entry.get("algorithm") if isinstance(entry, dict) else None
        if isinstance(alg, str) and alg not in found:
            found.append(alg)
    return found


def pinned(path):
    """(atcVersion, signature algorithms, expected verifyResult) of one fixture."""
    doc = json.loads(path.read_text(encoding="utf-8"))
    atx = doc.get("atx") if isinstance(doc, dict) else None
    atx = atx if isinstance(atx, dict) else {}
    expected = doc.get("expected") if isinstance(doc, dict) else None
    expected = expected if isinstance(expected, dict) else {}
    return atx.get("atcVersion"), algorithms(atx), expected.get("verifyResult")


def excepted_failures(text, paths):
    """(failures, summary) for the fixtures core.md section 12 excepts from the
    pinned-verdict requirement, compared with the suite's fixtures at paths."""
    failures = []
    facts = {}
    for path in paths:
        try:
            facts[path.stem] = pinned(path)
        except (OSError, ValueError, RecursionError) as exc:  # ValueError: not UTF-8, or not JSON
            failures.append(
                f"fixtures/{path.name} cannot be read as JSON ({exc}), so whether core.md "
                f"section 12 must except it from the pinned-verdict requirement is not known"
            )
    kind = {name for name, (version, algs, verdict) in facts.items()
            if version == "1.1" and verdict == "ACCEPT" and "ML-DSA-65" not in algs}

    lines = text.splitlines()
    suite_index, suite_where = section_12_line(lines, SUITE_ANCHOR)
    coverage_index, coverage_where = section_12_line(lines, COVERAGE_ANCHOR)
    suite_sentences = sentences_saying(lines, suite_index, EXCEPTS_RE)
    coverage_sentences = sentences_saying(lines, coverage_index, RULE_RE, EXCEPTS_RE)
    named = {name[: -len(".json")] if name.endswith(".json") else name
             for sentence in coverage_sentences for name in NAME_RE.findall(sentence)
             if not UPPERCASE_RE.search(name)}

    for name in sorted(kind - named):
        failures.append(
            f"{coverage_where} does not name {name} among the fixtures the pinned-verdict "
            f"requirement excepts, but fixtures/{name}.json {KIND} (signatures: "
            f"{', '.join(facts[name][1]) or 'none'}), which {RULE} rejects"
        )
    shipped = {path.stem for path in paths}
    for name in sorted(named - kind):
        if name not in shipped:
            failures.append(
                f"{coverage_where} names {name} among the fixtures the pinned-verdict requirement "
                f"excepts, but the suite ships no fixtures/{name}.json"
            )
        elif name in facts:  # a fixture that cannot be read as JSON is reported above
            version, algs, verdict = facts[name]
            failures.append(
                f"{coverage_where} names {name} among the fixtures the pinned-verdict requirement "
                f"excepts, but fixtures/{name}.json does not {KIND_PLURAL} (atcVersion "
                f"{json.dumps(version)}, signatures: {', '.join(algs) or 'none'}, verifyResult "
                f"{json.dumps(verdict)})"
            )

    stated = 0
    for where, sentences in ((suite_where, suite_sentences), (coverage_where, coverage_sentences)):
        for value, words in excepted_counts(sentences):
            stated += 1
            if value != len(kind):
                failures.append(
                    f"{where} states {value} (excepted fixtures: \"{words}\") but the suite "
                    f"ships {len(kind)} fixture(s) that {KIND_PLURAL}"
                )
    if kind and not suite_sentences:
        failures.append(
            f"{suite_where} does not except the {len(kind)} fixture(s) the suite ships that "
            f"{KIND_PLURAL} from the pinned-verdict requirement: no sentence of the Conformance "
            f"suite paragraph says \"excepts\", and {RULE} rejects each of them"
        )

    if kind:
        summary = (f"core.md section 12 excepts the {len(kind)} fixture(s) that {KIND_PLURAL}, "
                   f"and the {stated} count(s) of them it states match")
    else:
        summary = f"the suite ships no fixture that {KIND}, and core.md section 12 names none"
    return failures, summary


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--suite",
        required=True,
        help="path to a checkout of opena2a-standards/atx-conformance",
    )
    ap.add_argument("--root", default=str(ROOT), help="tree to check (default: this repository)")
    args = ap.parse_args()
    root = pathlib.Path(args.root).resolve()

    fixtures_dir = pathlib.Path(args.suite) / "fixtures"
    if not fixtures_dir.is_dir():
        print(f"no fixtures/ directory under {args.suite}", file=sys.stderr)
        return 1

    paths = sorted(fixtures_dir.glob("*.json"))
    actual = len(paths)
    if actual == 0:
        print("suite reports 0 fixtures; refusing to pass vacuously", file=sys.stderr)
        return 1

    failures = []
    checked = 0
    texts = {}

    for name, where in CLAIM_FILES.items():
        path = root / name
        if not path.exists():
            failures.append(f"{name} is missing")
            continue
        text = path.read_text(encoding="utf-8")
        texts[name] = text
        claims = stated_counts(text)
        if not claims:
            failures.append(
                f"{name} states no fixture count ({where}); the guard would pass "
                f"vacuously, so this is a failure"
            )
            continue
        newlines = [m.start() for m in NEWLINE_RE.finditer(text)]
        for kind, value, offset in claims:
            checked += 1
            # A run that passes every fixture reports no failures.
            expected = 0 if kind == "fail" else actual
            if value != expected:
                line = line_of(newlines, offset)
                if kind == "fail":
                    failures.append(
                        f"{name}:{line} states {value} ({kind}) but a run that passes "
                        f"all {actual} fixtures reports 0"
                    )
                else:
                    failures.append(
                        f"{name}:{line} states {value} ({kind}) but the suite ships {actual}"
                    )

    # A missing core.md is reported above; there is then no section 12 to compare.
    excepted, summary = ([], None)
    if EXCEPT_FILE in texts:
        excepted, summary = excepted_failures(texts[EXCEPT_FILE], paths)

    if failures or excepted:
        print("conformance counts are stale:\n", file=sys.stderr)
        for f in failures + excepted:
            print(f"  - {f}", file=sys.stderr)
        if failures:
            print(
                f"\natx-conformance ships {actual} fixtures. Update the count in "
                f"{', '.join(CLAIM_FILES)} and note it in CHANGELOG.md.",
                file=sys.stderr,
            )
        if excepted:
            print(
                f"\nName each fixture of atx-conformance that {KIND} in the Coverage "
                f"paragraph of {EXCEPT_FILE} section 12, state their number where section 12 "
                f"states it, and note it in CHANGELOG.md.",
                file=sys.stderr,
            )
        return 1

    print(
        f"conformance counts match: {actual} fixtures, "
        f"{checked} stated value(s) checked across {len(CLAIM_FILES)} documents; {summary}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
