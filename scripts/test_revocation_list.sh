#!/usr/bin/env bash
# Tests for scripts/check_revocation_list.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree and asserted to exit 1 naming the file, the line and the rule; the
# delivered tree itself is asserted to exit 0. Shell rather than pytest so it
# runs with nothing installed: bash and python3 are all this needs.
#
#   bash scripts/test_revocation_list.sh
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
    python3 -B "$REPO/scripts/check_revocation_list.py" --root "$1" > "$OUT" 2>&1
}

# The sizes scalability.md must state, at the ATP section 8.1 example entry size.
SIZES='The example entry in section 8.1 is 227 bytes, so each CRL entry is roughly 227 bytes and one million revocations is about 227 MB.'

new_tree() {  # new_tree <name> -> path to a scratch tree whose scalability.md states the sizes
    mkdir -p "$TMP/$1"
    printf '### 6.2 CRL size\n\n%s\n' "$SIZES" > "$TMP/$1/scalability.md"
    printf '%s' "$TMP/$1"
}

expect_fail() {  # expect_fail <leaf name> <root> <file:line> <rule>
    local name="$1" root="$2" where="$3" rule="$4" rc
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

# --- signed-crl -------------------------------------------------------------

T="$(new_tree signed-cache)"
printf '\nA verifier that loses network access continues using its cached CRL until the cache expires. The cache is signed, so a stale CRL cannot be tampered with.\n' >> "$T/scalability.md"
expect_fail "the cache called signed beside a stale CRL fails" "$T" "scalability.md:5" "signed-crl"

T="$(new_tree signed-list)"
printf 'Intro.\n\nThe CRL is signed by the issuing node.\n' > "$T/core.md"
expect_fail "a CRL called signed fails" "$T" "core.md:3" "signed-crl"

T="$(new_tree emphasis)"
printf 'The revocation list is **cryptographically signed**.\n' > "$T/core.md"
expect_fail "emphasis and an adverb do not hide the claim" "$T" "core.md:1" "signed-crl"

T="$(new_tree wrapped)"
printf 'Intro.\n\nVerifiers trust it because the cached\nCRL is\nsigned.\n' > "$T/sovereign-federation.md"
expect_fail "the claim split by soft line breaks fails" "$T" "sovereign-federation.md:4" "signed-crl"

T="$(new_tree not-signed)"
printf 'That revocation response body is **not signed** in ATP 1.0.\n' > "$T/core.md"
expect_pass "saying the response is not signed passes" "$T"

T="$(new_tree later-revision)"
printf 'A signed revocation list is ATP 1.1 work. In ATP 1.1 the revocation list is signed.\n' > "$T/core.md"
expect_pass "a sentence that places the signed list in ATP 1.1 passes" "$T"

T="$(new_tree transport-file)"
printf 'A sovereign can publish its CRL as a signed file. One way ingress via signed CRL files on physical media.\n' > "$T/sovereign-federation.md"
expect_pass "a CRL carried in a file signed for transport passes" "$T"

T="$(new_tree other-signed)"
printf 'The DID document cache is signed by the publisher. The STH is signed.\n' > "$T/core.md"
expect_pass "a signed object in a sentence that names no revocation passes" "$T"

# --- entry-size and total-size ----------------------------------------------

T="$(new_tree forty-bytes)"
printf '### 6.2 CRL size\n\nA full CRL listing every revoked agentId is small. Each entry is roughly 40 bytes\n(agentId plus revocation timestamp plus reason code). One million revocations is 40 MB.\n' > "$T/scalability.md"
expect_fail "an entry size below the section 8.1 example fails" "$T" "scalability.md:3" "entry-size"
expect_fail "a million revocations at 40 MB fails" "$T" "scalability.md:4" "total-size"

# 212 bytes is the section 8.1 example entry of the later ATP 1.1.0 draft, whose
# reason is a registered code. The v1.0.0-rc1 entry the specification cites is
# 227 bytes.
T="$(new_tree later-draft)"
printf '### 6.2 CRL size\n\nThe example entry in section 8.1 is 212 bytes, so each CRL entry is roughly 212 bytes\nand one million revocations is about 212 MB.\n' > "$T/scalability.md"
expect_fail "an entry at the 212 bytes of a later draft's example fails" "$T" "scalability.md:3" "entry-size"
expect_fail "a million revocations at 212 MB fails" "$T" "scalability.md:4" "total-size"

T="$(new_tree one-byte-short)"
printf 'Each CRL entry is 226 bytes.\n' > "$T/core.md"
run_check "$T"
if [ $? -eq 1 ] && grep -qF "core.md:1 [entry-size]" "$OUT" \
        && grep -qF "example entry is 227 bytes as compact JSON" "$OUT"; then
    ok "an entry one byte below the v1.0.0-rc1 example fails, and the failure names 227 bytes"
else
    not_ok "an entry one byte below the v1.0.0-rc1 example fails, and the failure names 227 bytes" \
        "$(head -c 400 "$OUT" | tr '\n' ' ')"
fi

T="$(new_tree table-row)"
printf '| Item | Size |\n|---|---|\n| CRL entry | 40 bytes |\n' > "$T/core.md"
expect_fail "an entry size in a table row fails" "$T" "core.md:3" "entry-size"

T="$(new_tree log-entry)"
printf 'A trillion entry log at 100 bytes per entry is 100 TB.\n' > "$T/core.md"
expect_pass "an entry size in a paragraph that names no revocation passes" "$T"

T="$(new_tree counts)"
printf 'Line one.\n\nA thousand revocations is 100 KB.\n\n1,000,000 revocations take 50 MB.\n' > "$T/core.md"
expect_fail "a thousand revocations at 100 KB fails" "$T" "core.md:3" "total-size"
expect_fail "a million revocations written in digits at 50 MB fails" "$T" "core.md:5" "total-size"

T="$(new_tree fractional)"
printf '2.5 million revocations is 567.5 MB. One billion revocations is about 227 GB.\n' > "$T/core.md"
expect_pass "totals at the section 8.1 entry size pass, fractional counts included" "$T"

T="$(new_tree no-figure)"
printf 'A delta covers about 5 minutes of revocations, typically a few KB.\n' > "$T/core.md"
expect_pass "a count of minutes is not a count of revocations" "$T"

# --- required statements ----------------------------------------------------

T="$TMP/missing"
mkdir -p "$T"
printf '### 6.2 CRL size\n\nThe CRL is small.\n' > "$T/scalability.md"
run_check "$T"
if [ $? -eq 1 ] && grep -qF "scalability.md [missing] states no revocation entry size" "$OUT" \
        && grep -qF "scalability.md [missing] states no revocation total size" "$OUT"; then
    ok "scalability.md that states no entry or total size fails"
else
    not_ok "scalability.md that states no entry or total size fails" "$(head -c 400 "$OUT" | tr '\n' ' ')"
fi

T="$TMP/no-scalability"
mkdir -p "$T"
printf 'Clean.\n' > "$T/core.md"
run_check "$T"
if [ $? -eq 1 ] && grep -qF "scalability.md [missing]" "$OUT"; then
    ok "a tree without scalability.md fails rather than passing vacuously"
else
    not_ok "a tree without scalability.md fails rather than passing vacuously" "$(head -c 400 "$OUT" | tr '\n' ' ')"
fi

# --- scope ------------------------------------------------------------------

T="$(new_tree history)"
mkdir -p "$T/errata"
printf -- '- Section 6.3 no longer says the cache is signed, so a stale CRL cannot be tampered with.\n' > "$T/CHANGELOG.md"
printf 'oldText: |\n  Each entry is roughly 40 bytes (agentId plus revocation timestamp). The cache is signed, so a stale CRL cannot be tampered with.\n' > "$T/errata/ATX-E-0001.md"
expect_pass "CHANGELOG.md and errata, which quote earlier text, are not checked" "$T"

T="$(new_tree nested)"
mkdir -p "$T/docs"
printf 'Line one.\nThe CRL is signed.\n' > "$T/docs/notes.md"
expect_fail "a Markdown file in a subdirectory is checked" "$T" "docs/notes.md:2" "signed-crl"

T="$(new_tree hidden-dir)"
mkdir -p "$T/.suite"
printf 'The CRL is signed.\n' > "$T/.suite/README.md"
expect_pass "hidden directories such as a suite checkout are not checked" "$T"

T="$(new_tree latin1)"
printf 'The CRL is small. Caf\351.\n' > "$T/notes.md"
run_check "$T"
if [ $? -eq 1 ] && grep -qF "notes.md [revocation-list] not UTF-8" "$OUT"; then
    ok "a file that is not UTF-8 fails rather than being skipped"
else
    not_ok "a file that is not UTF-8 fails rather than being skipped" "$(head -c 400 "$OUT" | tr '\n' ' ')"
fi

# --- vacuous pass -----------------------------------------------------------

T="$TMP/empty"
mkdir -p "$T"
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
