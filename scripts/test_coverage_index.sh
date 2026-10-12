#!/usr/bin/env bash
# Tests for scripts/check_coverage_index.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree and a scratch suite and asserted to exit 1 naming the place and the rule;
# the delivered core.md is asserted to exit 0 against a suite whose notCovered
# list cites the sections the atx-conformance suite cites. Shell rather than
# pytest so it runs with nothing installed: bash and python3 are all this needs.
#
#   bash scripts/test_coverage_index.sh
#
# Set ATX_CONFORMANCE_SUITE to a checkout of opena2a-standards/atx-conformance
# to also run the delivered core.md against the real suite; it is skipped
# otherwise. Output is TAP-ish: one line per leaf test. Exit 0 when every test
# passes.

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
    python3 -B "$REPO/scripts/check_coverage_index.py" --root "$1" --suite "$2" > "$OUT" 2>&1
}

new_dir() {  # new_dir <name> -> path to an empty scratch directory
    mkdir -p "$TMP/$1"
    printf '%s' "$TMP/$1"
}

expect_fail() {  # expect_fail <leaf name> <root> <suite> <where> <rule> [<detail>]
    local name="$1" root="$2" suite="$3" where="$4" rule="$5" detail="${6-}" rc
    run_check "$root" "$suite"
    rc=$?
    if [ "$rc" -ne 1 ]; then
        not_ok "$name" "expected exit 1, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
        return
    fi
    if ! grep -qF -- "$where [$rule]" "$OUT"; then
        not_ok "$name" "exit 1 but '$where [$rule]' not reported: $(head -c 400 "$OUT" | tr '\n' ' ')"
        return
    fi
    if [ -n "$detail" ] && ! grep -qF -- "$detail" "$OUT"; then
        not_ok "$name" "exit 1 but '$detail' not reported: $(head -c 400 "$OUT" | tr '\n' ' ')"
        return
    fi
    ok "$name"
}

expect_pass() {  # expect_pass <leaf name> <root> <suite>
    local name="$1" rc
    run_check "$2" "$3"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        ok "$name"
    else
        not_ok "$name" "expected exit 0, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
    fi
}

# write_core <root> <Coverage paragraph text> [<section 12 text before it>]
# The Coverage paragraph is on line 5.
write_core() {
    local before="${3-Three conformance targets exist.}"
    cat > "$1/core.md" <<EOF
## 12. Conformance

$before

**Coverage.** $2

## 13. Security considerations

Outside section 12, §9 is not read.
EOF
}

# write_suite <suite> <item> [<item> ...]
write_suite() {
    local suite="$1" first=1 item
    shift
    {
        printf '{\n  "notCovered": [\n'
        for item in "$@"; do
            [ "$first" -eq 1 ] || printf ',\n'
            first=0
            printf '    {"item": "%s", "reason": "no fixture"}' "$item"
        done
        printf '\n  ]\n}\n'
    } > "$suite/conformance.json"
}

# The sections the atx-conformance notCovered list cites, one item each.
UPSTREAM_ITEMS=(
    "Distinct signer-authority count (ATX core.md section 1.3 step 7)"
    "k-of-n threshold issuance (ATX core.md section 3.1 step 8)"
    "Cosignature requirements (ATX core.md section 7)"
    "Revocation propagation timing (ATX core.md section 3.3)"
    "Transparency-log monitor behavior (ATX core.md section 6.4)"
)
GOOD_PARA="Gaps: §1.3 step 7, §3.1 step 8, §7, §3.3 and §6.4."

# --- the delivered tree -----------------------------------------------------

S="$(new_dir upstream-suite)"
write_suite "$S" "${UPSTREAM_ITEMS[@]}"
expect_pass "the repository's own core.md names every section the suite's notCovered list cites" "$REPO" "$S"

if [ -n "${ATX_CONFORMANCE_SUITE-}" ]; then
    expect_pass "the repository's own core.md agrees with the real suite" "$REPO" "$ATX_CONFORMANCE_SUITE"
else
    skip "the repository's own core.md agrees with the real suite" "ATX_CONFORMANCE_SUITE not set"
fi

# --- coverage ---------------------------------------------------------------

T="$(new_dir agree)"
write_core "$T" "$GOOD_PARA"
expect_pass "a Coverage paragraph naming exactly the cited sections passes" "$T" "$S"

T="$(new_dir missing-3-1)"
write_core "$T" "Gaps: §1.3 step 7, §7, §3.3 and §6.4."
expect_fail "a section notCovered cites and the Coverage paragraph does not name fails" \
    "$T" "$S" "core.md:5" coverage "notCovered cites section 3.1"

T="$(new_dir extra-9)"
write_core "$T" "$GOOD_PARA Also §9."
expect_fail "a section the Coverage paragraph names and no notCovered item cites fails" \
    "$T" "$S" "core.md:5" coverage "names §9 as uncovered"

T="$(new_dir named-elsewhere)"
write_core "$T" "Gaps: §1.3 step 7, §7, §3.3 and §6.4." "Threshold issuance is §3.1 step 8."
expect_fail "a section named in another paragraph of section 12 does not count" \
    "$T" "$S" "core.md:5" coverage "notCovered cites section 3.1"

S2="$(new_dir lowercase-suite)"
write_suite "$S2" "Distinct signer-authority count (section 1.3 step 7)" "Timing (Section 3.3)"
T="$(new_dir lowercase)"
write_core "$T" "Gaps: §1.3 step 7 and §3.3."
expect_pass "an item citing 'section' or 'Section' counts" "$T" "$S2"

# --- uncited ----------------------------------------------------------------

S3="$(new_dir uncited-suite)"
write_suite "$S3" "${UPSTREAM_ITEMS[@]}" "Monitor gossip, with no section"
T="$(new_dir uncited)"
write_core "$T" "$GOOD_PARA"
expect_fail "a notCovered item that cites no section fails" \
    "$T" "$S3" "conformance.json notCovered[5]" uncited

# --- vacuous pass -----------------------------------------------------------

T="$(new_dir no-anchor)"
write_core "$T" "$GOOD_PARA"
sed 's/^\*\*Coverage\.\*\*/**Gaps.**/' "$T/core.md" > "$T/core.tmp" && mv "$T/core.tmp" "$T/core.md"
expect_fail "a renamed Coverage paragraph fails instead of passing vacuously" \
    "$T" "$S" "core.md" coverage "no line opening with **Coverage.**"

T="$(new_dir no-core)"
expect_fail "a tree with no core.md fails instead of passing vacuously" \
    "$T" "$S" "core.md" coverage "file not found"

T="$(new_dir no-index)"
write_core "$T" "$GOOD_PARA"
S4="$(new_dir no-index-suite)"
expect_fail "a suite with no conformance.json fails instead of passing vacuously" \
    "$T" "$S4" "conformance.json" notCovered

S5="$(new_dir empty-suite)"
write_suite "$S5"
expect_fail "an empty notCovered list fails instead of passing vacuously" \
    "$T" "$S5" "conformance.json" notCovered "an empty one"

# --- summary ----------------------------------------------------------------

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d of %d test(s) failed\n' "$FAILED" "$COUNT"
    exit 1
fi
printf '# %d test(s) passed, %d skipped\n' "$((COUNT - SKIPPED))" "$SKIPPED"
