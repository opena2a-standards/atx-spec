#!/usr/bin/env bash
# Tests for scripts/check_revocation_cursor.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree and asserted to exit 1 naming the file, the line and the rule; the
# delivered tree itself is asserted to exit 0. Shell rather than pytest so it
# runs with nothing installed: bash and python3 are all this needs.
#
#   bash scripts/test_revocation_cursor.sh
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
    python3 -B "$REPO/scripts/check_revocation_cursor.py" --root "$1" > "$OUT" 2>&1
}

new_tree() {  # new_tree <name> -> path to an empty scratch tree
    mkdir -p "$TMP/$1"
    printf '%s' "$TMP/$1"
}

expect_fail() {  # expect_fail <leaf name> <root> <file:line>
    local name="$1" root="$2" where="$3" rc
    run_check "$root"
    rc=$?
    if [ "$rc" -ne 1 ]; then
        not_ok "$name" "expected exit 1, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
        return
    fi
    if ! grep -qF -- "$where [crl-version]" "$OUT"; then
        not_ok "$name" "exit 1 but '$where [crl-version]' not reported: $(head -c 400 "$OUT" | tr '\n' ' ')"
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

# --- crl-version ------------------------------------------------------------

T="$(new_tree revocation-step)"
cat > "$T/core.md" <<'EOF'
### 3.3 Revocation flow

1. Revocation trigger fires.
2. Issuing node marks ATX as revoked. Adds REVOCATION entry to transparency log. Increments CRL version.
EOF
expect_fail "a revocation step that increments a CRL version fails" "$T" "core.md:4"

T="$(new_tree wrapped)"
printf 'Intro.\n\nVerifiers compare the cached CRL\nversion with the published one.\n' > "$T/scalability.md"
expect_fail "the phrase split by a soft line break fails" "$T" "scalability.md:3"

T="$(new_tree long-form)"
printf 'The node bumps its Revocation-List Version on every entry.\n' > "$T/sovereign-federation.md"
expect_fail "revocation list version fails in any case and with a hyphen" \
    "$T" "sovereign-federation.md:1"

T="$(new_tree cursor)"
printf 'Advances the `nextSince` cursor that the ATP-SPEC v1.0.0-rc1 section 8.1 revocation response returns.\n' > "$T/core.md"
expect_pass "naming the nextSince cursor passes" "$T"

T="$(new_tree other-versions)"
printf 'Check atxVersion is supported. The CRL is versioned by STH. Document version: 1.1.0.\n' > "$T/core.md"
expect_pass "other version words near CRL are not the phrase" "$T"

T="$(new_tree history)"
mkdir -p "$T/errata"
printf 'Clean.\n' > "$T/core.md"
printf -- '- Step 2 no longer says Increments CRL version.\n' > "$T/CHANGELOG.md"
printf 'oldText: |\n  Increments CRL version.\n' > "$T/errata/ATX-E-0001.md"
expect_pass "CHANGELOG.md and errata, which quote earlier text, are not checked" "$T"

T="$(new_tree nested)"
mkdir -p "$T/docs"
printf 'Clean.\n' > "$T/README.md"
printf 'Line one.\nThe CRL version advances.\n' > "$T/docs/notes.md"
expect_fail "a Markdown file in a subdirectory is checked" "$T" "docs/notes.md:2"

T="$(new_tree hidden-dir)"
mkdir -p "$T/.suite"
printf 'Clean.\n' > "$T/README.md"
printf 'The CRL version advances.\n' > "$T/.suite/README.md"
expect_pass "hidden directories such as a suite checkout are not checked" "$T"

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
