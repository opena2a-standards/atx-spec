#!/usr/bin/env bash
# Tests for scripts/check_validity_window.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree and asserted to exit 1 naming the file, the line and the rule; the
# delivered tree itself is asserted to exit 0. Shell rather than pytest so it
# runs with nothing installed: bash and python3 are all this needs.
#
#   bash scripts/test_validity_window.sh
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

run_check() {  # run_check <root>
    python3 -B "$REPO/scripts/check_validity_window.py" --root "$1" > "$OUT" 2>&1
}

new_tree() {  # new_tree <name> -> path to an empty scratch tree
    mkdir -p "$TMP/$1"
    printf '%s' "$TMP/$1"
}

expect_fail() {  # expect_fail <leaf name> <root> <file:line> [rule, default expiry-alone]
    local name="$1" root="$2" where="$3" rule="${4:-expiry-alone}" rc
    run_check "$root"
    rc=$?
    if [ "$rc" -ne 1 ]; then
        not_ok "$name" "expected exit 1, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
        return
    fi
    if ! grep -qF -- "$where [$rule]" "$OUT"; then
        not_ok "$name" "exit 1 but '$where [$rule]' not reported: $(head -c 400 "$OUT" | tr '\n' ' ')"
        return
    fi
    ok "$name"
}

expect_pass() {  # expect_pass <leaf name> <root>
    local name="$1" root="$2" rc
    run_check "$root"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        ok "$name"
    else
        not_ok "$name" "expected exit 0, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
    fi
}

# --- the delivered tree -----------------------------------------------------

expect_pass "the repository's own Markdown passes" "$REPO"

# --- expiry-alone -----------------------------------------------------------

T="$(new_tree verification-flow)"
cat > "$T/core.md" <<'EOF'
### 3.2 Verification flow

1. Verifier receives request.
2. Parse ATX. Check atcVersion is supported. Check expiresAt is in the future. Under 0.1ms.
3. Look up issuerDid in local DID document cache.
EOF
expect_fail "a verification step that checks expiresAt alone fails" "$T" "core.md:4"

T="$(new_tree window-step)"
cat > "$T/core.md" <<'EOF'
### 1.3 Local verification algorithm

1. Parse ATX. Validate schema version is supported.
2. Check the validity window against the verifier's clock. The ATX is expired at the earlier of `expiresAt` and `issuedAt` plus the seven-day credential TTL of §1.2, and it is not yet valid while `issuedAt` is in the future. An expired or not-yet-valid ATX rejects immediately.
EOF
expect_pass "a step that names issuedAt beside expiresAt passes" "$T"

T="$(new_tree wrapped)"
printf 'Intro.\n\nThe verifier checks that\n`expiresAt` is later than its clock.\n' > "$T/scalability.md"
expect_fail "a step wrapped by a soft line break fails on the line naming expiresAt" \
    "$T" "scalability.md:4"

T="$(new_tree wrapped-window)"
printf 'The verifier checks that `expiresAt`\nand `issuedAt` bound its clock.\n' > "$T/scalability.md"
expect_pass "issuedAt on the continuation line of the same step passes" "$T"

T="$(new_tree next-item)"
cat > "$T/core.md" <<'EOF'
1. Check expiresAt is in the future.
2. Check issuedAt is not in the future.
EOF
expect_fail "issuedAt in the next list item does not complete the step before it" "$T" "core.md:1"

T="$(new_tree next-paragraph)"
printf 'A verifier rejects an ATX past its expiresAt.\n\nThe issuedAt member is RFC 3339.\n' > "$T/core.md"
expect_fail "issuedAt past a blank line does not complete the step" "$T" "core.md:1"

T="$(new_tree nested-item)"
printf -- '- Check `expiresAt`.\n  - Then check `issuedAt`.\n' > "$T/core.md"
expect_fail "issuedAt in a nested list item does not complete the step above it" "$T" "core.md:1"

T="$(new_tree table-cell)"
cat > "$T/core.md" <<'EOF'
| Plane | Work | Fields |
|---|---|---|
| Verification | Reject when expiresAt has passed | issuedAt |
EOF
expect_fail "issuedAt in another table cell does not complete the cell that checks expiresAt" \
    "$T" "core.md:3"

for VERB in check Checks checked checking verify VERIFIES verified verifying validate validates \
    validated validating compare compares compared comparing reject Rejects rejected rejecting; do
    T="$(new_tree "verb-$VERB")"
    printf 'The verifier %s expiresAt against its clock.\n' "$VERB" > "$T/core.md"
    expect_fail "the check verb '$VERB' with expiresAt alone fails" "$T" "core.md:1"
done

T="$(new_tree field-only)"
cat > "$T/core.md" <<'EOF'
| Field | Form |
|---|---|
| expiresAt (RFC 3339, UTC) | "1.0" |

The canonical form places `contentHash` and `expiresAt` in that order.
EOF
expect_pass "naming expiresAt with no check verb passes" "$T"

T="$(new_tree expiry-word)"
printf 'Signature check. Expiry check. Revocation cache check.\n' > "$T/core.md"
expect_pass "an expiry check that names neither timestamp is not a restatement of step 2" "$T"

T="$(new_tree checksum)"
printf 'The checksum covers expiresAt. A verifiable credential carries expiresAt.\n' > "$T/core.md"
expect_pass "a word that only begins with a check verb is not one" "$T"

T="$(new_tree history)"
mkdir -p "$T/errata"
printf 'Clean.\n' > "$T/core.md"
printf -- '- Step 2 no longer says Check expiresAt is in the future.\n' > "$T/CHANGELOG.md"
printf 'oldText: |\n  2. Check expiresAt is in the future.\n' > "$T/errata/ATX-E-0001.md"
expect_pass "CHANGELOG.md and errata, which quote earlier text, are not checked" "$T"

T="$(new_tree nested)"
mkdir -p "$T/docs"
printf 'Clean.\n' > "$T/README.md"
printf 'Line one.\n\nCheck expiresAt is in the future.\n' > "$T/docs/notes.md"
expect_fail "a Markdown file in a subdirectory is checked" "$T" "docs/notes.md:3"

T="$(new_tree hidden-dir)"
mkdir -p "$T/.suite"
printf 'Clean.\n' > "$T/README.md"
printf 'Check expiresAt is in the future.\n' > "$T/.suite/README.md"
expect_pass "hidden directories such as a suite checkout are not checked" "$T"

T="$(new_tree not-utf8)"
printf 'Clean.\n' > "$T/README.md"
printf 'Check expiresAt \xff is in the future.\n' > "$T/core.md"
run_check "$T"
if [ $? -eq 1 ] && grep -qF "core.md [not-utf-8]" "$OUT"; then
    ok "a file that is not UTF-8 fails instead of being skipped"
else
    not_ok "a file that is not UTF-8 fails instead of being skipped" \
        "$(head -c 400 "$OUT" | tr '\n' ' ')"
fi

# --- vacuous pass -----------------------------------------------------------

T="$(new_tree empty)"
run_check "$T"
if [ $? -eq 1 ] && grep -q "refusing to pass vacuously" "$OUT"; then
    ok "a tree with no Markdown files exits 1 instead of passing vacuously"
else
    not_ok "a tree with no Markdown files exits 1 instead of passing vacuously" \
        "$(head -c 400 "$OUT" | tr '\n' ' ')"
fi

# --- summary ----------------------------------------------------------------

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d of %d test(s) failed\n' "$FAILED" "$COUNT"
    exit 1
fi
printf '# %d test(s) passed\n' "$COUNT"
