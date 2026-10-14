#!/usr/bin/env bash
# Tests for scripts/check_conformance_counts.py.
#
# Each phrasing the check reads is built here in a scratch tree with a scratch
# suite of a known size, and a stated count that differs from it is asserted to
# exit 1 naming the file, the line and the kind of count. The delivered README.md,
# docs/conformance.md and core.md are asserted to agree with each other: they
# pass against a suite of the size core.md section 12 states. Shell rather than
# pytest so it runs with nothing installed: bash and python3 are all this needs.
#
#   bash scripts/test_conformance_counts.sh
#
# Output is TAP-ish: one line per leaf test. Exit 0 when every test passes.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/out.txt"

COUNT=0
FAILED=0

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

run_check() {  # run_check <root> <suite>
    python3 -B "$REPO/scripts/check_conformance_counts.py" --root "$1" --suite "$2" > "$OUT" 2>&1
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
    expect_pass "README.md, docs/conformance.md and core.md agree with the count core.md states" \
        "$REPO" "$(suite "$STATED")"
    expect_fail "the delivered tree fails on its summary fixture count against a suite that has moved" \
        "$REPO" "$(suite $((STATED + 2)))" "README.md:$SUMMARY_LINE states $STATED (fixtures)"
    expect_fail "the delivered tree fails on its summary pass count against a suite that has moved" \
        "$REPO" "$(suite $((STATED + 2)))" "README.md:$SUMMARY_LINE states $STATED (pass)"
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

T="$(tree core-stale $'# Title\n\nThe suite ships 5 fixtures.' $'# Core\n\n7 fixtures (baseline).')"
expect_fail "a stale count in core.md fails" "$T" "$(suite 5)" "core.md:3 states 7 (fixtures)"

T="$(tree docs-stale $'# Title\n\nThe suite ships 5 fixtures.' "$CORE" \
    $'# Conformance\n\nThe suite ships 5 fixtures. Both verifiers report 7 of 7 PASS.')"
expect_fail "a stale pass count in docs/conformance.md fails" "$T" "$(suite 5)" \
    "docs/conformance.md:3 states 7 (pass)"

# --- vacuous pass -----------------------------------------------------------

T="$(tree no-count $'# Title\n\nNo count here.')"
expect_fail "a README.md that states no count fails instead of passing vacuously" \
    "$T" "$(suite 5)" "README.md states no fixture count"

mkdir -p "$TMP/suite-empty/fixtures"
T="$(tree empty-suite $'# Title\n\nThe suite ships 5 fixtures.')"
expect_fail "a suite with no fixtures fails instead of passing vacuously" \
    "$T" "$TMP/suite-empty" "refusing to pass vacuously"

# --- summary ----------------------------------------------------------------

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d of %d test(s) failed\n' "$FAILED" "$COUNT"
    exit 1
fi
printf '# %d test(s) passed\n' "$COUNT"
