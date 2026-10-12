#!/usr/bin/env bash
# Tests for scripts/check_atp_claims.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree and asserted to exit 1 naming the file, the line and the rule; the
# delivered tree itself is asserted to exit 0. Shell rather than pytest so it
# runs with nothing installed: bash and python3 are all this needs.
#
#   bash scripts/test_atp_claims.sh
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
    python3 -B "$REPO/scripts/check_atp_claims.py" --root "$1" > "$OUT" 2>&1
}

new_tree() {  # new_tree <name> -> path to an empty scratch tree
    mkdir -p "$TMP/$1"
    printf '%s' "$TMP/$1"
}

expect_fail() {  # expect_fail <leaf name> <root> <file:line> [rule, default negotiation]
    local name="$1" root="$2" where="$3" rule="${4:-negotiation}" rc
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

# --- negotiation ------------------------------------------------------------

T="$(new_tree suite-bullet)"
cat > "$T/core.md" <<'EOF'
## 10. What ATX is not

* **ATX does not bind to a single cryptographic suite.** Ed25519 and ML-DSA-65 are mandatory today. Additional suites can be added via ATP version negotiation.
EOF
expect_fail "a suite added via ATP version negotiation fails" "$T" "core.md:3"

T="$(new_tree registry-row)"
cat > "$T/core.md" <<'EOF'
| Registry | Governed set | Change policy |
|---|---|---|
| Signature algorithm suites | `Ed25519`, `ML-DSA-65` | Specification revision via ATP version negotiation (§10). |
EOF
expect_fail "a registry change policy citing ATP version negotiation fails" "$T" "core.md:3"

T="$(new_tree wrapped)"
printf 'Intro.\n\nSuites are agreed when ATP\npeers Negotiate them at connection time.\n' > "$T/scalability.md"
expect_fail "ATP and a negotiation split by a soft line break fail, in any case" \
    "$T" "scalability.md:4"

T="$(new_tree version-only)"
printf 'A verifier picks the credential form by version negotiation with the holder.\n' > "$T/sovereign-federation.md"
expect_fail "a version negotiation that does not name ATP fails" "$T" "sovereign-federation.md:1"

T="$(new_tree negotiation-first)"
printf 'Negotiation selects the suite, as ATP-SPEC v1.0.0-rc1 §4.2 describes.\n' > "$T/core.md"
expect_fail "a negotiation named before ATP in the same sentence fails" "$T" "core.md:1"

T="$(new_tree revision)"
printf 'Additional suites are added by specification revision (§14). See ATP-SPEC v1.0.0-rc1 §1.3a.2.\n' > "$T/core.md"
expect_pass "a suite added by specification revision passes" "$T"

T="$(new_tree other-sentence)"
printf 'Federation partners negotiate a peering agreement. ATP carries the trust list.\n\nThe version\n\nis negotiated elsewhere.\n' > "$T/sovereign-federation.md"
expect_pass "a negotiation in one sentence and ATP in the next, or past a blank line, passes" "$T"

T="$(new_tree history)"
mkdir -p "$T/errata"
printf 'Clean.\n' > "$T/core.md"
printf -- '- Section 10 no longer says suites are added via ATP version negotiation.\n' > "$T/CHANGELOG.md"
printf 'oldText: |\n  Additional suites can be added via ATP version negotiation.\n' > "$T/errata/ATX-E-0001.md"
expect_pass "CHANGELOG.md and errata, which quote earlier text, are not checked" "$T"

T="$(new_tree nested)"
mkdir -p "$T/docs"
printf 'Clean.\n' > "$T/README.md"
printf 'Line one.\nATP negotiates the suite.\n' > "$T/docs/notes.md"
expect_fail "a Markdown file in a subdirectory is checked" "$T" "docs/notes.md:2"

T="$(new_tree hidden-dir)"
mkdir -p "$T/.suite"
printf 'Clean.\n' > "$T/README.md"
printf 'ATP negotiates the suite.\n' > "$T/.suite/README.md"
expect_pass "hidden directories such as a suite checkout are not checked" "$T"

# --- wg-draft ---------------------------------------------------------------

T="$(new_tree wg-sentence)"
cat > "$T/core.md" <<'EOF'
ATP is the standards play. ATX is the wedge. We push ATP into IETF as a Working Group draft. We push the transparency log conformance criteria into the same model the WebPKI uses for CA acceptance.
EOF
expect_fail "ATP pushed into IETF as a Working Group draft fails" "$T" "core.md:1" wg-draft

T="$(new_tree wg-wrapped)"
printf 'Intro.\n\nATP is a working-group\nInternet-Draft.\n' > "$T/README.md"
expect_fail "a working-group Internet-Draft split by a soft line break fails" \
    "$T" "README.md:3" wg-draft

T="$(new_tree wg-abbrev)"
printf 'ATP became a WG draft in July.\n' > "$T/scalability.md"
expect_fail "the WG draft abbreviation fails" "$T" "scalability.md:1" wg-draft

T="$(new_tree wg-intended)"
printf 'We intend to submit ATP to the IETF as an individual Internet-Draft and to seek its adoption by a working group.\n' > "$T/core.md"
expect_pass "IETF work described as intended passes" "$T"

T="$(new_tree wg-history)"
mkdir -p "$T/errata"
printf 'Clean.\n' > "$T/core.md"
printf -- '- Section 2 no longer says ATP is pushed into IETF as a Working Group draft.\n' > "$T/CHANGELOG.md"
printf 'oldText: |\n  We push ATP into IETF as a Working Group draft.\n' > "$T/errata/ATX-E-0001.md"
expect_pass "CHANGELOG.md and errata quoting the old claim are not checked" "$T"

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
