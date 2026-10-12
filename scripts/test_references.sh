#!/usr/bin/env bash
# Tests for scripts/check_references.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree and asserted to exit 1 naming the file, the line and the rule; the
# delivered tree itself is asserted to exit 0. Shell rather than pytest so it
# runs with nothing installed: bash and python3 are all this needs.
#
#   bash scripts/test_references.sh
#
# Output is TAP-ish: one line per leaf test. Exit 0 when every test passes.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ATP='https://github.com/opena2a-standards/agent-trust-protocol'

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

run_check() {  # run_check <root> [extra args...]
    python3 -B "$REPO/scripts/check_references.py" --root "$@" > "$OUT" 2>&1
}

new_tree() {  # new_tree <name> -> path to an empty scratch tree
    mkdir -p "$TMP/$1"
    printf '%s' "$TMP/$1"
}

expect_fail() {  # expect_fail <leaf name> <root> <rule> <where>
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

expect_pass_within() {  # expect_pass_within <leaf name> <root> <seconds>
    local name="$1" root="$2" limit="$3" rc start elapsed
    start=$SECONDS
    run_check "$root"
    rc=$?
    elapsed=$((SECONDS - start))
    if [ "$rc" -ne 0 ]; then
        not_ok "$name" "expected exit 0, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
    elif [ "$elapsed" -gt "$limit" ]; then
        not_ok "$name" "took ${elapsed} s"
    else
        ok "$name (took ${elapsed} s)"
    fi
}

# --- the delivered tree -----------------------------------------------------

expect_pass "the repository's own Markdown passes" "$REPO"

# --- owner ------------------------------------------------------------------

T="$(new_tree owner-url)"
printf 'Intro.\n\nSee [ATP](https://github.com/opena2a-org/agent-trust-protocol) for the wire protocol.\n' \
    > "$T/README.md"
expect_fail "a URL under the old owner of a standards repository fails" \
    "$T" owner "README.md:3"

T="$(new_tree owner-text)"
printf 'The vectors live in\n[`opena2a-org/atx-conformance`](https://github.com/opena2a-standards/atx-conformance).\n' \
    > "$T/core.md"
expect_fail "link text naming the old owner fails even when the URL is current" \
    "$T" owner "core.md:2"

T="$(new_tree owner-sentence-end)"
printf 'The identity layer is opena2a-org/agent-identity-protocol.\n' > "$T/core.md"
expect_fail "a path that ends a sentence is still matched" \
    "$T" owner "core.md:1"

T="$(new_tree owner-current)"
printf 'See [ATP](%s) and [AIM](https://github.com/opena2a-org/agent-identity-management).\n' "$ATP" \
    > "$T/README.md"
expect_pass "the current owner, and a repository that still lives under opena2a-org, pass" "$T"

T="$(new_tree owner-other-repo)"
printf 'See opena2a-org/atx-spec-tools and opena2a-org/atx-spec.md-notes.\n' > "$T/README.md"
expect_pass "a longer repository name that only starts with a standards name passes" "$T"

T="$(new_tree owner-history)"
mkdir -p "$T/errata"
printf 'Clean.\n' > "$T/README.md"
printf -- '- Links to opena2a-org/agent-trust-protocol now name opena2a-standards.\n' > "$T/CHANGELOG.md"
printf 'oldText: see opena2a-org/agent-trust-protocol\n' > "$T/errata/ATX-E-0001.md"
expect_pass "CHANGELOG.md and errata/ quote earlier text and are not checked" "$T"

T="$(new_tree owner-nested)"
mkdir -p "$T/docs"
printf 'Clean.\n' > "$T/README.md"
printf 'Line one.\nSee opena2a-org/agent-trust-protocol.\n' > "$T/docs/guide.md"
expect_fail "a Markdown file in a subdirectory is checked" \
    "$T" owner "docs/guide.md:2"

# --- version ----------------------------------------------------------------

T="$(new_tree version-root)"
printf '# core\n\nSpecified in [ATP-SPEC v1.0.0-rc1](%s); this document follows it.\n' "$ATP" \
    > "$T/core.md"
expect_fail "a link that cites a version and points at the repository root fails" \
    "$T" version "core.md:3"

T="$(new_tree version-main)"
printf 'Specified in [ATP-SPEC v1.0.0-rc1](%s/blob/main/ATP-SPEC.md).\n' "$ATP" > "$T/core.md"
expect_fail "a link that cites a version and points at the default branch fails" \
    "$T" version "core.md:1"

T="$(new_tree version-other-tag)"
printf 'Specified in [ATP-SPEC v1.0.0-rc1](%s/blob/v1.0.0/ATP-SPEC.md).\n' "$ATP" > "$T/core.md"
expect_fail "a link pinned to a different tag fails" \
    "$T" version "core.md:1"

T="$(new_tree version-wrapped)"
printf 'Intro.\n\nSpecified in [ATP-SPEC\nv1.0.0-rc1](%s).\n' "$ATP" > "$T/core.md"
expect_fail "link text that wraps across a line break is read whole" \
    "$T" version "core.md:3"

T="$(new_tree version-blob)"
printf 'Specified in [ATP-SPEC v1.0.0-rc1](%s/blob/v1.0.0-rc1/ATP-SPEC.md).\n' "$ATP" > "$T/core.md"
expect_pass "a link pinned to the cited tag through /blob/ passes" "$T"

T="$(new_tree version-tree)"
printf 'Specified in [ATP-SPEC v1.0.0-rc1](%s/tree/v1.0.0-rc1).\n' "$ATP" > "$T/core.md"
expect_pass "a link pinned to the cited tag through /tree/ passes" "$T"

T="$(new_tree version-unversioned)"
printf 'See [the ATP repository](%s) and [v1.0.0-rc1](https://specs.example.org/atp).\n' "$ATP" \
    > "$T/core.md"
expect_pass "unversioned link text, and a target outside GitHub, are not checked" "$T"

# --- wire-name --------------------------------------------------------------

T="$(new_tree wire-step)"
cat > "$T/core.md" <<'EOF'
# Verify

1. Fetch the issuer key.
2. Parse ATX. Check atxVersion is supported. Check expiresAt is in the future.
EOF
expect_fail "a verification step that checks atxVersion fails" \
    "$T" wire-name "core.md:4"

T="$(new_tree wire-next-sentence)"
printf 'The field is atcVersion. A verifier reads atxVersion first.\n' > "$T/core.md"
expect_fail "naming atcVersion in an earlier sentence does not cover atxVersion" \
    "$T" wire-name "core.md:1"

T="$(new_tree wire-table)"
printf '| Member | Note |\n|---|---|\n| atxVersion | read before atcVersion is known |\n' > "$T/core.md"
expect_fail "atcVersion in another table cell does not cover atxVersion" \
    "$T" wire-name "core.md:3"

T="$(new_tree wire-alias)"
printf 'The version field is named `atcVersion` on the wire (earlier revisions\nused the alias `atxVersion`).\n' \
    > "$T/core.md"
expect_pass "a sentence that names atcVersion may record the old alias across a line break" "$T"

T="$(new_tree wire-other-word)"
printf 'The atxVersions table and myatxVersion are other words.\n' > "$T/core.md"
expect_pass "a longer word that contains atxVersion is not the alias" "$T"

# --- encoding, usage and pathological input ---------------------------------

T="$(new_tree encoding)"
printf 'Clean.\n' > "$T/README.md"
printf 'Line one.\n\xff\xfe broken\n' > "$T/core.md"
expect_fail "a file that is not UTF-8 is reported" \
    "$T" encoding "core.md:2"

T="$(new_tree spaces-after-link-paren)"
python3 -B -c "open('$T/doc.md', 'w').write('See [a](' + ' ' * 200000)"
expect_pass_within "200000 spaces after a link's opening parenthesis are checked in under 10 s" \
    "$T" 10

T="$(new_tree open-brackets)"
python3 -B -c "open('$T/doc.md', 'w').write('[' * 200000)"
expect_pass_within "200000 unclosed brackets are checked in under 10 s" \
    "$T" 10

run_check "$REPO" --bogus
RC=$?
python3 -B "$REPO/scripts/check_references.py" --help > "$TMP/help.txt" 2>&1
if [ "$RC" -eq 2 ] && grep -q "and 2 on" "$TMP/help.txt" && grep -q "usage error" "$TMP/help.txt"; then
    ok "an unknown option exits 2, and --help documents exit 2"
else
    not_ok "an unknown option exits 2, and --help documents exit 2" \
        "exit $RC; help: $(head -c 400 "$TMP/help.txt" | tr '\n' ' ')"
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
