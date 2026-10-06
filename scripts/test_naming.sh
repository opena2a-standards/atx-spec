#!/usr/bin/env bash
# Tests for scripts/check_naming.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree and asserted to exit 1 naming the file, the line and the rule; the
# delivered tree itself is asserted to exit 0. Shell rather than pytest so it
# runs with nothing installed: bash and python3 are all this needs.
#
#   bash scripts/test_naming.sh
#
# Output is TAP-ish: one line per leaf test. Exit 0 when every test passes.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PHRASE="OpenA2A AIM (Agent Identity Management)"
LINK="https://github.com/opena2a-org/agent-identity-management"

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
    python3 -B "$REPO/scripts/check_naming.py" --root "$1" > "$OUT" 2>&1
}

new_tree() {  # new_tree <name> -> path to an empty scratch tree
    mkdir -p "$TMP/$1"
    printf '%s' "$TMP/$1"
}

expect_fail() {  # expect_fail <leaf name> <root> <rule> <file:line>
    local name="$1" root="$2" rule="$3" where="$4" rc
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

# --- first-use --------------------------------------------------------------

T="$(new_tree nav-bar-bare)"
cat > "$T/README.md" <<EOF
> **specs** · [AIM]($LINK)

# spec

$PHRASE verifies credentials.
EOF
expect_fail "a bare AIM link in the navigation bar ahead of the expansion fails" \
    "$T" first-use "README.md:1"

T="$(new_tree nav-bar-expanded)"
cat > "$T/README.md" <<EOF
> **specs** · [$PHRASE]($LINK)

# spec

AIM verifies credentials.
EOF
expect_pass "the expansion in the navigation bar link counts as first use" "$T"

T="$(new_tree same-line-bare)"
printf 'AIM, that is %s, verifies credentials.\n' "$PHRASE" > "$T/core.md"
expect_fail "a bare AIM earlier on the line that carries the expansion fails" \
    "$T" first-use "core.md:1"

T="$(new_tree other-expansion)"
printf '# Agent Identity Management (AIM)\n\nAIM verifies credentials.\n' > "$T/README.md"
expect_fail "an expansion in another form does not satisfy the rule" \
    "$T" first-use "README.md:1"

T="$(new_tree wrapped)"
printf 'Intro.\n\nThe platform is OpenA2A AIM (Agent\nIdentity Management). AIM verifies.\n' > "$T/core.md"
expect_pass "the phrase may wrap across a soft line break" "$T"

T="$(new_tree aims)"
printf 'The working group document defines AIMS. aim and Aim are ordinary words.\n' > "$T/core.md"
expect_pass "AIMS and lowercase aim are not uses of AIM" "$T"

T="$(new_tree nested)"
mkdir -p "$T/errata"
printf 'Clean.\n' > "$T/README.md"
printf 'Line one.\nAIM rejects the credential.\n' > "$T/errata/ATX-E-0001.md"
expect_fail "a Markdown file in a subdirectory is checked" \
    "$T" first-use "errata/ATX-E-0001.md:2"

T="$(new_tree hidden-dir)"
mkdir -p "$T/.suite"
printf 'Clean.\n' > "$T/README.md"
printf 'AIM ARIA\n' > "$T/.suite/README.md"
expect_pass "hidden directories such as a suite checkout are not checked" "$T"

# --- product-name -----------------------------------------------------------

T="$(new_tree aria-table)"
printf '| Plane | Owner |\n|---|---|\n| Intelligence | ARIA plus NanoMind |\n' > "$T/core.md"
expect_fail "ARIA in a table cell fails" "$T" product-name "core.md:3"

T="$(new_tree trust-layer)"
printf 'Intro.\n\nThe OpenA2A Trust Layer issues credentials.\n' > "$T/README.md"
expect_fail "trust layer as a name fails in any case" "$T" product-name "README.md:3"

T="$(new_tree trust-layer-wrapped)"
printf 'The trust\nlayer issues credentials.\n' > "$T/README.md"
expect_fail "trust layer split by a soft line break fails" "$T" product-name "README.md:1"

T="$(new_tree wai-aria)"
printf 'The browser extension follows WAI-ARIA for its warning banner.\n' > "$T/README.md"
expect_pass "WAI-ARIA, the accessibility specification, is allowed" "$T"

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
