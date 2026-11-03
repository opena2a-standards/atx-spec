#!/usr/bin/env bash
# Tests for scripts/check_conformance_counts.py.
#
# Each phrasing the check reads is built here in a scratch tree with a scratch
# suite of a known size, and a stated count that differs from it, or a summary
# line's fail count other than 0, is asserted to exit 1 naming the file, the
# line and the kind of count. The delivered README.md, docs/conformance.md and
# core.md are asserted to agree with each other: they pass against a suite of
# the size core.md section 12 states. Shell rather than pytest so it runs with
# nothing installed: bash and python3 are all this needs.
#
# The fixtures section 12 excepts from the pinned-verdict requirement are tested
# the same way: scratch suites of fixtures that pin ACCEPT or REJECT on
# atcVersion 1.0 or 1.1 credentials with and without an ML-DSA-65 entry, against
# scratch Conformance suite and Coverage paragraphs that name them and state
# their number. The delivered core.md passes against a suite whose fixtures that
# pin ACCEPT on an atcVersion 1.1 credential declaring no ML-DSA-65 entry are the
# ones its Coverage paragraph names, and fails against one that adds another.
#
#   bash scripts/test_conformance_counts.sh
#
# Set ATX_CONFORMANCE_SUITE to a checkout of opena2a-standards/atx-conformance
# to also run the delivered README.md, docs/conformance.md and core.md against
# the real suite; it is skipped otherwise. Output is TAP-ish: one line per leaf
# test. Exit 0 when every test passes.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/out.txt"

COUNT=0
FAILED=0
SKIPPED=0

ok() {  # ok <leaf test name>
    COUNT=$((COUNT + 1))
    printf 'ok %d - %s\n' "$COUNT" "$1"
}

not_ok() {  # not_ok <leaf test name> <why>
    COUNT=$((COUNT + 1))
    FAILED=$((FAILED + 1))
    printf 'not ok %d - %s\n' "$COUNT" "$1"
    printf '  ---\n  reason: %s\n  ---\n' "$2"
}

skip() {  # skip <leaf test name> <why>
    COUNT=$((COUNT + 1))
    SKIPPED=$((SKIPPED + 1))
    printf 'ok %d - %s # SKIP %s\n' "$COUNT" "$1" "$2"
}

run_check() {  # run_check <root> <suite>
    python3 -B "$REPO/scripts/check_conformance_counts.py" --root "$1" --suite "$2" > "$OUT" 2>&1
}

run_check_within() {  # run_check_within <seconds> <root> <suite>: exit 124 when it takes longer
    python3 -B - "$1" "$REPO/scripts/check_conformance_counts.py" "$2" "$3" > "$OUT" 2>&1 <<'PYEOF'
import subprocess, sys
limit, script, root, suite = float(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
try:
    sys.exit(subprocess.run([sys.executable, "-B", script, "--root", root, "--suite", suite],
                            timeout=limit).returncode)
except subprocess.TimeoutExpired:
    print(f"still running after {limit:g} s")
    sys.exit(124)
PYEOF
}

suite() {  # suite <n> -> path to a scratch suite shipping <n> fixtures
    local dir="$TMP/suite-$1" i
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir/fixtures"
        for i in $(seq 1 "$1"); do
            printf '{}\n' > "$dir/fixtures/fixture-$i.json"
        done
    fi
    printf '%s' "$dir"
}

fixture() {  # fixture <kind> -> the JSON of a scratch fixture of that kind
    case "$1" in
        # Pins ACCEPT on an atcVersion 1.1 credential that declares no ML-DSA-65
        # entry, which the required-suites rule of core.md section 1.3 step 5 rejects.
        class)    printf '%s\n' '{"atx": {"atcVersion": "1.1", "signatures": [{"algorithm": "Ed25519"}]}, "expected": {"verifyResult": "ACCEPT"}}' ;;
        unsigned) printf '%s\n' '{"atx": {"atcVersion": "1.1", "signatures": []}, "expected": {"verifyResult": "ACCEPT"}}' ;;
        hybrid)   printf '%s\n' '{"atx": {"atcVersion": "1.1", "signatures": [{"algorithm": "Ed25519"}, {"algorithm": "ML-DSA-65"}]}, "expected": {"verifyResult": "ACCEPT"}}' ;;
        reject)   printf '%s\n' '{"atx": {"atcVersion": "1.1", "signatures": [{"algorithm": "Ed25519"}]}, "expected": {"verifyResult": "REJECT", "rejectCategory": "SIGNATURE_INVALID"}}' ;;
        legacy)   printf '%s\n' '{"atx": {"atcVersion": "1.0", "signatures": [{"algorithm": "Ed25519"}]}, "expected": {"verifyResult": "ACCEPT"}}' ;;
        broken)   printf '%s\n' '{"atx": ' ;;
        *)        printf '%s\n' '{}' ;;
    esac
}

xsuite() {  # xsuite <name> <fixture name>:<kind>... -> path to a scratch suite of those fixtures
    local dir="$TMP/suite-$1" spec
    shift
    mkdir -p "$dir/fixtures"
    for spec in "$@"; do
        fixture "${spec#*:}" > "$dir/fixtures/${spec%%:*}.json"
    done
    printf '%s' "$dir"
}

# The fixtures the Coverage paragraph of the delivered core.md names as excepted
# from the pinned-verdict requirement, one per line: each name in backticks that
# holds no uppercase letter, in a sentence of the section 12 line opening with
# **Coverage.** that names the required-suites rule or says "excepts".
python3 -B - "$REPO/core.md" > "$TMP/excepted.txt" <<'PYEOF'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
start = next((i for i, line in enumerate(lines) if line.startswith("## 12. Conformance")), None)
for line in lines[start + 1:] if start is not None else []:
    if line.startswith("## "):
        break
    if line.startswith("**Coverage.**"):
        for sentence in re.split(r"(?<=[.!?])\s+", line):
            if "required-suites rule" in sentence or re.search(r"\bexcepts\b", sentence):
                for name in re.findall(r"`([^`\s]+)`", sentence):
                    if not re.search(r"[A-Z]", name):
                        print(name[: -len(".json")] if name.endswith(".json") else name)
        break
PYEOF
EXCEPTED="$(sort -u "$TMP/excepted.txt")"

delivered_suite() {  # delivered_suite <n> [<name>] -> path to a scratch suite of <n> fixtures
    # Each fixture the delivered core.md excepts, and <name> when given, pins ACCEPT on
    # an atcVersion 1.1 credential that declares no ML-DSA-65 entry; the rest are {}.
    local dir="$TMP/delivered-$1-${2-}" name made=0
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir/fixtures"
        for name in $EXCEPTED ${2-}; do
            fixture class > "$dir/fixtures/$name.json"
            made=$((made + 1))
        done
        while [ "$made" -lt "$1" ]; do
            made=$((made + 1))
            printf '{}\n' > "$dir/fixtures/fixture-$made.json"
        done
    fi
    printf '%s' "$dir"
}

CORE=$'# Core\n\n## 12. Conformance\n\nThe suite: 5 fixtures (baseline, hybrid).'
DOCS=$'# Conformance\n\nThe suite ships 5 fixtures.'

# tree <name> <README.md text> [<core.md text> [<docs/conformance.md text>]]
#   -> path to a scratch tree
tree() {
    local t="$TMP/$1"
    mkdir -p "$t/docs"
    printf '%s\n' "$2" > "$t/README.md"
    printf '%s\n' "${3-$CORE}" > "$t/core.md"
    printf '%s\n' "${4-$DOCS}" > "$t/docs/conformance.md"
    printf '%s' "$t"
}

expect_fail() {  # expect_fail <leaf name> <root> <suite> <reported text>
    local name="$1" rc
    run_check "$2" "$3"
    rc=$?
    if [ "$rc" -ne 1 ]; then
        not_ok "$name" "expected exit 1, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
        return
    fi
    if ! grep -qF -- "$4" "$OUT"; then
        not_ok "$name" "exit 1 but '$4' not reported: $(head -c 400 "$OUT" | tr '\n' ' ')"
        return
    fi
    ok "$name"
}

expect_pass() {  # expect_pass <leaf name> <root> <suite> [<reported text>]
    local name="$1" rc
    run_check "$2" "$3"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        not_ok "$name" "expected exit 0, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
        return
    fi
    if [ -n "${4-}" ] && ! grep -qF -- "$4" "$OUT"; then
        not_ok "$name" "exit 0 but '$4' not reported: $(head -c 400 "$OUT" | tr '\n' ' ')"
        return
    fi
    ok "$name"
}

# --- the delivered tree -----------------------------------------------------

STATED="$(grep -oE '[0-9]+ fixtures \(' "$REPO/core.md" | head -1 | grep -oE '^[0-9]+')"
SUMMARY_LINE="$(grep -n '# summary: [0-9]* pass, 0 fail' "$REPO/README.md" | head -1 | cut -d: -f1)"
if [ -z "$STATED" ] || [ -z "$SUMMARY_LINE" ]; then
    not_ok "core.md states a fixture count and README.md a summary line" \
        "core.md count '$STATED', README.md summary line '$SUMMARY_LINE'"
else
    ok "core.md states a fixture count and README.md a summary line"
    expect_pass "README.md, docs/conformance.md and core.md agree with the count core.md states and with the fixtures its Coverage paragraph excepts" \
        "$REPO" "$(delivered_suite "$STATED")"
    expect_fail "the delivered tree fails on its summary fixture count against a suite that has moved" \
        "$REPO" "$(delivered_suite $((STATED + 2)))" "README.md:$SUMMARY_LINE states $STATED (fixtures)"
    expect_fail "the delivered tree fails on its summary pass count against a suite that has moved" \
        "$REPO" "$(delivered_suite $((STATED + 2)))" "README.md:$SUMMARY_LINE states $STATED (pass)"
fi

COVERAGE_LINE="$(grep -n '^\*\*Coverage\.\*\*' "$REPO/core.md" | head -1 | cut -d: -f1)"
if [ -z "$STATED" ] || [ -z "$COVERAGE_LINE" ]; then
    not_ok "core.md has a Coverage paragraph" \
        "core.md count '$STATED', Coverage line '$COVERAGE_LINE'"
else
    expect_fail "the delivered core.md fails against a suite that ships a fixture pinning ACCEPT on an atcVersion 1.1 credential with no ML-DSA-65 entry that its Coverage paragraph does not name" \
        "$REPO" "$(delivered_suite "$STATED" v1_1-unnamed-ed25519-only)" \
        "core.md:$COVERAGE_LINE does not name v1_1-unnamed-ed25519-only among the fixtures the pinned-verdict requirement excepts"
fi

if [ -n "${ATX_CONFORMANCE_SUITE-}" ]; then
    expect_pass "README.md, docs/conformance.md and core.md state the count the real suite ships, and core.md names the fixtures of it section 12 excepts" \
        "$REPO" "$ATX_CONFORMANCE_SUITE"
else
    skip "README.md, docs/conformance.md and core.md state the count the real suite ships, and core.md names the fixtures of it section 12 excepts" \
        "ATX_CONFORMANCE_SUITE not set"
fi

# --- phrasings --------------------------------------------------------------

T="$(tree plain $'# Title\n\nThe suite ships 5 fixtures.')"
expect_pass "a count equal to the suite passes" "$T" "$(suite 5)" "3 stated value(s) checked"

T="$(tree plain-stale $'# Title\n\nThe suite ships 7 fixtures.')"
expect_fail "a stale 'N fixtures' fails" "$T" "$(suite 5)" "README.md:3 states 7 (fixtures)"

T="$(tree byte-pinned $'# Title\n\nThe suite ships 5 fixtures.\n\nIt ships 7 byte-pinned fixtures.')"
expect_fail "a stale 'N byte-pinned fixtures' fails" "$T" "$(suite 5)" \
    "README.md:5 states 7 (fixtures)"

T="$(tree pinned $'# Title\n\nThe suite ships 5 fixtures.\n\nIt ships 7 pinned fixtures.')"
expect_fail "a stale 'N pinned fixtures' fails" "$T" "$(suite 5)" "README.md:5 states 7 (fixtures)"

T="$(tree subset $'# Title\n\nThe suite ships 5 fixtures, 3 hybrid fixtures among them.')"
expect_pass "a count of a subset ('3 hybrid fixtures') is not compared with the suite" \
    "$T" "$(suite 5)" "3 stated value(s) checked"

T="$(tree of-pass $'# Title\n\nThe suite ships 5 fixtures. Both report 4 of 5 PASS.')"
expect_fail "a stale 'N of M PASS' fails on the pass count" "$T" "$(suite 5)" \
    "README.md:3 states 4 (pass)"

T="$(tree summary-pass $'# Title\n\n```\n# summary: 4 pass, 0 fail (5 fixtures)\n```')"
expect_fail "a stale 'N pass, 0 fail' summary line fails" "$T" "$(suite 5)" \
    "README.md:4 states 4 (pass)"

T="$(tree summary-fixtures $'# Title\n\n```\n# summary: 5 pass, 0 fail (7 fixtures)\n```')"
expect_fail "a stale fixture count in a summary line fails" "$T" "$(suite 5)" \
    "README.md:4 states 7 (fixtures)"

T="$(tree summary-ok $'# Title\n\n```\n# summary: 5 pass, 0 fail (5 fixtures)\n```')"
expect_pass "a summary line stating every fixture passed and 0 failed passes, its fail count read" \
    "$T" "$(suite 5)" "5 stated value(s) checked"

T="$(tree summary-fail $'# Title\n\n```\n# summary: 5 pass, 1 fail (5 fixtures)\n```')"
expect_fail "a summary line stating a failure fails" "$T" "$(suite 5)" \
    "README.md:4 states 1 (fail) but a run that passes all 5 fixtures reports 0"

T="$(tree summary-moved $'# Title\n\n```\n# summary: 4 pass, 1 fail (5 fixtures)\n```')"
expect_fail "a summary line moving one fixture from pass to fail reports the pass count" \
    "$T" "$(suite 5)" "README.md:4 states 4 (pass)"
expect_fail "a summary line moving one fixture from pass to fail reports the fail count" \
    "$T" "$(suite 5)" "README.md:4 states 1 (fail)"

T="$(tree docs-summary-fail $'# Title\n\nThe suite ships 5 fixtures.' "$CORE" \
    $'# Conformance\n\nThe suite ships 5 fixtures.\n\nThe verifier prints 5 pass, 2 fail.')"
expect_fail "a fail count other than 0 in docs/conformance.md fails" "$T" "$(suite 5)" \
    "docs/conformance.md:5 states 2 (fail)"

T="$(tree core-stale $'# Title\n\nThe suite ships 5 fixtures.' $'# Core\n\n7 fixtures (baseline).')"
expect_fail "a stale count in core.md fails" "$T" "$(suite 5)" "core.md:3 states 7 (fixtures)"

T="$(tree docs-stale $'# Title\n\nThe suite ships 5 fixtures.' "$CORE" \
    $'# Conformance\n\nThe suite ships 5 fixtures. Both verifiers report 7 of 7 PASS.')"
expect_fail "a stale pass count in docs/conformance.md fails" "$T" "$(suite 5)" \
    "docs/conformance.md:3 states 7 (pass)"

# --- the fixtures section 12 excepts ------------------------------------------

# xcore <suite size> <Conformance suite clause> <Coverage sentences> -> core.md
# text with the Conformance suite paragraph on line 5 and the Coverage paragraph
# on line 7. The Coverage paragraph opens with a sentence that names a fixture
# outside the exception, as the delivered one does.
xcore() {
    printf '%s\n' "# Core" "" "## 12. Conformance" "" \
        "**Conformance suite.** The suite ships $1 fixtures, and an implementation MUST produce the pinned verdict on every fixture$2." "" \
        "**Coverage.** The \`threshold-1of3-cosignature\` fixture pins a rejection.$3"
}

xtree() {  # xtree <name> <suite size> <core.md text> -> path to a scratch tree that states that size
    tree "$1" "$(printf '# Title\n\nThe suite ships %s fixtures.' "$2")" "$3" \
        "$(printf '# Conformance\n\nThe suite ships %s fixtures.' "$2")"
}

SUITE_TWO=' other than the two that the Coverage paragraph below excepts'
COVER_TWO=' Two fixtures, `a-1` and `a-2`, declare `atcVersion` 1.1, carry Ed25519 signatures only and pin ACCEPT, while the required-suites rule of §1.3 step 5 rejects each of them as a signature failure (`SIGNATURE_INVALID`). Until the suite regenerates them, a conforming verifier rejects each of the two, and the pinned-verdict requirement of the Conformance suite paragraph above excepts them.'
COVER_JSON=' Two fixtures, `a-1.json` and `a-2.json`, declare `atcVersion` 1.1 and pin ACCEPT, while the required-suites rule of §1.3 step 5 rejects each of them. A conforming verifier rejects each of the two, and the pinned-verdict requirement above excepts them.'
COVER_NINE=' Two fixtures, `a-1` and `a-9`, declare `atcVersion` 1.1 and pin ACCEPT, while the required-suites rule of §1.3 step 5 rejects each of them. A conforming verifier rejects each of the two, and the pinned-verdict requirement above excepts them.'
CLASS='pins ACCEPT on an atcVersion 1.1 credential that declares no ML-DSA-65 entry'

# Fixtures that carry an ML-DSA-65 entry, pin REJECT or declare atcVersion 1.0 are
# not of the kind the exception names, and `threshold-1of3-cosignature`, named in
# another sentence of the Coverage paragraph, is not read as an excepted fixture.
S="$(xsuite x-ok a-1:class a-2:class b-1:hybrid b-2:reject b-3:legacy)"
T="$(xtree x-ok 5 "$(xcore 5 "$SUITE_TWO" "$COVER_TWO")")"
expect_pass "an exception that names each fixture pinning ACCEPT on a v1.1 credential with no ML-DSA-65 entry, and states their number, passes" \
    "$T" "$S" "core.md section 12 excepts the 2 fixture(s)"

S2="$(xsuite x-two a-1:class a-2:class)"
T="$(xtree x-json 2 "$(xcore 2 "$SUITE_TWO" "$COVER_JSON")")"
expect_pass "a name written with .json is read as that fixture" "$T" "$S2" \
    "core.md section 12 excepts the 2 fixture(s)"

# The suite ships a third fixture of the kind while section 12 names two of them.
S="$(xsuite x-unnamed a-1:class a-2:class a-3:class)"
T="$(xtree x-unnamed 3 "$(xcore 3 "$SUITE_TWO" "$COVER_TWO")")"
expect_fail "a fixture of that kind the Coverage paragraph does not name fails, named" "$T" "$S" \
    "core.md:7 does not name a-3 among the fixtures the pinned-verdict requirement excepts, but fixtures/a-3.json $CLASS (signatures: Ed25519)"
expect_fail "a number of them the Conformance suite paragraph states fails once the suite ships another" \
    "$T" "$S" "core.md:5 states 2 (excepted fixtures: \"the two\") but the suite ships 3 fixture(s)"
expect_fail "'N fixtures' in the Coverage paragraph fails once the suite ships another" \
    "$T" "$S" "core.md:7 states 2 (excepted fixtures: \"Two fixtures\") but the suite ships 3 fixture(s)"
expect_fail "'each of the N' in the Coverage paragraph fails once the suite ships another" \
    "$T" "$S" "core.md:7 states 2 (excepted fixtures: \"the two\") but the suite ships 3 fixture(s)"

S="$(xsuite x-unsigned a-1:class a-2:class u-1:unsigned)"
T="$(xtree x-unsigned 3 "$(xcore 3 "$SUITE_TWO" "$COVER_TWO")")"
expect_fail "a v1.1 fixture that declares no signature and pins ACCEPT is one the exception must name" \
    "$T" "$S" "core.md:7 does not name u-1 among the fixtures the pinned-verdict requirement excepts, but fixtures/u-1.json $CLASS (signatures: none)"

T="$(xtree x-suite-three 2 "$(xcore 2 ' other than the three that the Coverage paragraph below excepts' "$COVER_TWO")")"
expect_fail "a number the Conformance suite paragraph states that differs from the fixtures of that kind fails" \
    "$T" "$S2" "core.md:5 states 3 (excepted fixtures: \"the three\") but the suite ships 2 fixture(s)"

T="$(xtree x-suite-numeral 2 "$(xcore 2 ' other than the 3 that the Coverage paragraph below excepts' "$COVER_TWO")")"
expect_fail "a number of them written as a numeral is read" "$T" "$S2" \
    "core.md:5 states 3 (excepted fixtures: \"the 3\") but the suite ships 2 fixture(s)"

T="$(xtree x-each 2 "$(xcore 2 "$SUITE_TWO" "${COVER_TWO/each of the two/each of the three}")")"
expect_fail "'each of the N' in the Coverage paragraph is read as their number" "$T" "$S2" \
    "core.md:7 states 3 (excepted fixtures: \"the three\") but the suite ships 2 fixture(s)"

T="$(xtree x-not-shipped 2 "$(xcore 2 "$SUITE_TWO" "$COVER_NINE")")"
expect_fail "a name the suite ships no fixture for fails" "$T" "$S2" \
    "core.md:7 names a-9 among the fixtures the pinned-verdict requirement excepts, but the suite ships no fixtures/a-9.json"

S="$(xsuite x-named-hybrid a-1:class a-2:hybrid)"
T="$(xtree x-named-hybrid 2 "$(xcore 2 "$SUITE_TWO" "$COVER_TWO")")"
expect_fail "a named fixture that declares an ML-DSA-65 entry fails" "$T" "$S" \
    "core.md:7 names a-2 among the fixtures the pinned-verdict requirement excepts, but fixtures/a-2.json does not pin ACCEPT on an atcVersion 1.1 credential that declares no ML-DSA-65 entry (atcVersion \"1.1\", signatures: Ed25519, ML-DSA-65, verifyResult \"ACCEPT\")"

S="$(xsuite x-named-reject a-1:class a-2:reject)"
T="$(xtree x-named-reject 2 "$(xcore 2 "$SUITE_TWO" "$COVER_TWO")")"
expect_fail "a named fixture that pins REJECT fails" "$T" "$S" \
    "core.md:7 names a-2 among the fixtures the pinned-verdict requirement excepts, but fixtures/a-2.json does not pin ACCEPT on an atcVersion 1.1 credential that declares no ML-DSA-65 entry (atcVersion \"1.1\", signatures: Ed25519, verifyResult \"REJECT\")"

S="$(xsuite x-named-legacy a-1:class a-2:legacy)"
T="$(xtree x-named-legacy 2 "$(xcore 2 "$SUITE_TWO" "$COVER_TWO")")"
expect_fail "a named fixture that declares atcVersion 1.0 fails" "$T" "$S" \
    "core.md:7 names a-2 among the fixtures the pinned-verdict requirement excepts, but fixtures/a-2.json does not pin ACCEPT on an atcVersion 1.1 credential that declares no ML-DSA-65 entry (atcVersion \"1.0\", signatures: Ed25519, verifyResult \"ACCEPT\")"

# The suite regenerates every fixture section 12 names with an ML-DSA-65 entry.
S="$(xsuite x-regenerated a-1:hybrid a-2:hybrid)"
T="$(xtree x-regenerated 2 "$(xcore 2 "$SUITE_TWO" "$COVER_TWO")")"
expect_fail "an exception left in place once the suite regenerates the fixtures it names fails on each name" \
    "$T" "$S" "core.md:7 names a-1 among the fixtures the pinned-verdict requirement excepts, but fixtures/a-1.json does not pin ACCEPT"
expect_fail "an exception left in place once the suite regenerates the fixtures it names fails on its number" \
    "$T" "$S" "core.md:5 states 2 (excepted fixtures: \"the two\") but the suite ships 0 fixture(s)"

T="$(xtree x-no-excepts 2 "$(xcore 2 "" "$COVER_TWO")")"
expect_fail "a Conformance suite paragraph that excepts no fixture fails while the suite ships fixtures of that kind" \
    "$T" "$S2" "core.md:5 does not except the 2 fixture(s) the suite ships that pin ACCEPT on an atcVersion 1.1 credential that declares no ML-DSA-65 entry from the pinned-verdict requirement"

S="$(xsuite x-no-coverage a-1:class a-2:legacy)"
T="$(xtree x-no-coverage 2 $'# Core\n\n## 12. Conformance\n\nThe suite ships 2 fixtures.')"
expect_fail "a fixture of that kind fails when section 12 has no Coverage paragraph to name it" \
    "$T" "$S" "core.md (section 12 has no line opening with **Coverage.**) does not name a-1"
expect_fail "a fixture of that kind fails when section 12 has no Conformance suite paragraph to except it" \
    "$T" "$S" "core.md (section 12 has no line opening with **Conformance suite.**) does not except the 1 fixture(s)"

T="$(xtree x-no-section 2 $'# Core\n\nThe suite ships 2 fixtures.')"
expect_fail "a fixture of that kind fails when core.md has no section 12" \
    "$T" "$S" "core.md (it has no ## 12. Conformance heading) does not name a-1"

S="$(xsuite x-broken a-1:class a-2:class b-1:broken)"
T="$(xtree x-broken 3 "$(xcore 3 "$SUITE_TWO" "$COVER_TWO")")"
expect_fail "a fixture that cannot be read as JSON fails, as whether the exception must name it is not known" \
    "$T" "$S" "fixtures/b-1.json cannot be read as JSON"

# --- vacuous pass -----------------------------------------------------------

T="$(tree no-count $'# Title\n\nNo count here.')"
expect_fail "a README.md that states no count fails instead of passing vacuously" \
    "$T" "$(suite 5)" "README.md states no fixture count"

mkdir -p "$TMP/suite-empty/fixtures"
T="$(tree empty-suite $'# Title\n\nThe suite ships 5 fixtures.')"
expect_fail "a suite with no fixtures fails instead of passing vacuously" \
    "$T" "$TMP/suite-empty" "refusing to pass vacuously"

# --- time -------------------------------------------------------------------

# Each stale count's line was found by counting newlines from the start of the
# file, which took time quadratic in the number of stale counts.
T="$(tree many-stale $'# Title')"
python3 -B - "$T/README.md" <<'PYEOF'
import sys
with open(sys.argv[1], "a", encoding="utf-8") as f:
    f.write("\n" + "7 fixtures\n" * 150000)
PYEOF
run_check_within 10 "$T" "$(suite 5)"
rc=$?
if [ "$rc" -eq 1 ] && grep -qF "README.md:150002 states 7 (fixtures)" "$OUT"; then
    ok "a 1.65 MB README.md of 150,000 stale counts is checked in time, the last on its own line"
else
    not_ok "a 1.65 MB README.md of 150,000 stale counts is checked in time, the last on its own line" \
        "expected exit 1 within 10 s reporting README.md:150002, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
fi

# --- summary ----------------------------------------------------------------

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d of %d test(s) failed\n' "$FAILED" "$COUNT"
    exit 1
fi
printf '# %d test(s) passed, %d skipped\n' "$((COUNT - SKIPPED))" "$SKIPPED"
