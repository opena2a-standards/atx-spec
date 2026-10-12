#!/usr/bin/env bash
# Tests for scripts/check_mediation.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree and asserted to exit 1 naming the file, the line and the rule; the
# delivered tree itself is asserted to exit 0. Shell rather than pytest so it
# runs with nothing installed: bash and python3 are all this needs.
#
#   bash scripts/test_mediation.sh
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
    python3 -B "$REPO/scripts/check_mediation.py" --root "$1" > "$OUT" 2>&1
}

new_tree() {  # new_tree <name> -> path to a scratch tree whose required files pass
    mkdir -p "$TMP/$1"
    printf 'An issuer not on the list is rejected as an untrusted issuer.\n' > "$TMP/$1/core.md"
    printf 'The verifier rejects an untrusted issuer.\n' > "$TMP/$1/sovereign-federation.md"
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

T="$(new_tree baseline)"
expect_pass "a scratch tree holding only the required statements passes" "$T"

# --- verify-path ------------------------------------------------------------

T="$(new_tree query-in-list)"
cat > "$T/notes.md" <<'EOF'
## 7. Cross org cosigning

1. Agent A presents ATX issued by node X.
2. Agent B's verifier checks: is node X in B's trusted federation list? If yes, accept if valid.
3. If node X is not in B's trusted list, B queries the root node (OpenA2A) for a cosignature.
EOF
expect_fail "a list step that has B query the root for a cosignature fails" \
    "$T" verify-path "notes.md:5"

T="$(new_tree passive)"
printf 'A verifier checking an ATX from an unlisted authority falls back. The root node may be\nqueried for a neutral cosignature.\n' > "$T/notes.md"
expect_fail "a passive query wrapped onto the next line fails on the verb's line" \
    "$T" verify-path "notes.md:2"

T="$(new_tree dotted-did)"
cat > "$T/notes.md" <<'EOF'
3. Verifier in Y looks up gov.x. Not on local trust list.
4. Verifier requests a cosignature from the root authority (did:opena2a:authority:opena2a.org).
EOF
expect_fail "a sentence with a dotted DID in it is still read whole" \
    "$T" verify-path "notes.md:2"

T="$(new_tree countersignature)"
printf 'During verification the verifier fetches a countersignature from the root.\n' > "$T/notes.md"
expect_fail "fetching a countersignature during verification fails" \
    "$T" verify-path "notes.md:1"

T="$(new_tree negated)"
cat > "$T/notes.md" <<'EOF'
3. If node X is not in B's trusted list, B's verifier rejects it. B does not query the root node or any other authority for a cosignature.

It does not fall back to asking the root, or anyone else, for a cosignature. A verifier never requests a cosignature.
EOF
expect_pass "a negated request states the rule and passes" "$T"

T="$(new_tree issuance)"
cat > "$T/notes.md" <<'EOF'
Verification is local.
9. If a sovereign node is in the issuerChain, the issuing node requests cosignature from that node's API.
The root cosignature is requested at issuance.
EOF
expect_pass "a request at issuance passes beside verification text" "$T"

T="$(new_tree no-verifier)"
printf '* **Federation gateway.** Manages bilateral relationships, cosignature requests.\n' > "$T/notes.md"
expect_pass "a cosignature request in a block that names no verifier passes" "$T"

T="$(new_tree table)"
cat > "$T/notes.md" <<'EOF'
| Dimension | ATX model |
|---|---|
| Verification | Network query per interaction |
| Posture | Federate and cosign |
EOF
expect_pass "a table row is its own sentence, so a query and a cosign in two rows pass" "$T"

# --- chain-order ------------------------------------------------------------

T="$(new_tree root-last)"
printf 'Intro.\n6. Cosigned ATX has issuerChain = [gov.x, opena2a.org].\n' > "$T/notes.md"
expect_fail "a chain naming the root last fails" "$T" chain-order "notes.md:2"

T="$(new_tree json-root-last)"
cat > "$T/notes.md" <<'EOF'
```json
{
  "issuerChain": [
    "did:opena2a:authority:gov.x",
    "did:opena2a:authority:opena2a.org"
  ]
}
```
EOF
expect_fail "a JSON chain naming the root second fails" "$T" chain-order "notes.md:3"

T="$(new_tree root-first)"
cat > "$T/notes.md" <<'EOF'
The issuing node writes `issuerChain` = [did:opena2a:authority:opena2a.org, did:opena2a:authority:gov.x] before gov.x signs.

```json
{ "issuerChain": [ "did:opena2a:authority:opena2a.org" ] }
```

A chain without the root, issuerChain = [gov.x, gov.y], is not this rule's concern.
EOF
expect_pass "root-first, root-only and root-less chains pass" "$T"

# --- missing ----------------------------------------------------------------

T="$(new_tree missing-core)"
printf 'Unlisted issuers are handled somehow.\n' > "$T/core.md"
expect_fail "core.md saying nothing about an untrusted issuer fails" "$T" missing "core.md"

T="$(new_tree missing-file)"
rm "$T/sovereign-federation.md"
expect_fail "a missing sovereign-federation.md fails instead of passing vacuously" \
    "$T" missing "sovereign-federation.md"

T="$(new_tree wrapped-phrase)"
printf 'Rejected as an untrusted\nissuer.\n' > "$T/core.md"
expect_pass "the required phrase may wrap across lines" "$T"

# --- scope ------------------------------------------------------------------

T="$(new_tree history)"
mkdir -p "$T/errata"
printf -- '- The verifier no longer queries the root.\n  Old: Verifier requests a cosignature from the root. issuerChain = [gov.x, opena2a.org].\n' > "$T/CHANGELOG.md"
printf 'oldText: |\n  Verifier requests a cosignature from the root.\n' > "$T/errata/ATX-E-0001.md"
expect_pass "CHANGELOG.md and errata, which quote earlier text, are not checked" "$T"

T="$(new_tree hidden-dir)"
mkdir -p "$T/.suite"
printf 'Verifier requests a cosignature from the root.\n' > "$T/.suite/README.md"
expect_pass "hidden directories such as a suite checkout are not checked" "$T"

T="$(new_tree nested)"
mkdir -p "$T/docs"
printf 'Line one.\nThe verifier requests a cosignature from the root.\n' > "$T/docs/notes.md"
expect_fail "a Markdown file in a subdirectory is checked" "$T" verify-path "docs/notes.md:2"

T="$(new_tree not-utf8)"
printf 'Verifier \xff\xfe text.\n' > "$T/notes.md"
expect_fail "a file that is not UTF-8 fails rather than being skipped" "$T" encoding "notes.md:1"

# --- vacuous pass -----------------------------------------------------------

mkdir -p "$TMP/empty"
run_check "$TMP/empty"
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
