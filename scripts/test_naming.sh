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

run_check() {  # run_check <root> [extra arguments]
    python3 -B "$REPO/scripts/check_naming.py" --root "$1" "${@:2}" > "$OUT" 2>&1
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

expect_pass_within() {  # expect_pass_within <leaf name> <root> <seconds>
    local name="$1" root="$2" limit="$3" started elapsed rc
    started=$(date +%s)
    run_check "$root"
    rc=$?
    elapsed=$(( $(date +%s) - started ))
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

T="$(new_tree node-modules)"
mkdir -p "$T/node_modules/pkg"
printf 'Clean.\n' > "$T/README.md"
printf 'AIM ARIA\n' > "$T/node_modules/pkg/README.md"
expect_pass "Markdown under node_modules is not checked" "$T"

T="$(new_tree claim-ahead)"
printf 'CLAIM and RECLAIM come first. %s verifies them.\n' "$PHRASE" > "$T/core.md"
expect_pass "an uppercase word ending in AIM ahead of the expansion is not a use of AIM" "$T"

T="$(new_tree comment-only)"
printf '<!-- %s -->\n\nAIM verifies credentials.\n' "$PHRASE" > "$T/doc.md"
expect_fail "the expansion inside an HTML comment, which a reader does not see, fails" \
    "$T" first-use "doc.md:1"

T="$(new_tree comment-bare)"
printf '<!--\nAIM -->\n\nAIM verifies credentials.\n' > "$T/doc.md"
expect_fail "a bare AIM inside an HTML comment still counts as the first use" \
    "$T" first-use "doc.md:2"

T="$(new_tree comment-then-visible)"
printf '<!-- reviewed -->\n\n%s verifies credentials. AIM rejects.\n' "$PHRASE" > "$T/doc.md"
expect_pass "a comment without AIM ahead of the visible expansion passes" "$T"

T="$(new_tree title-only)"
printf '[home](%s "%s")\n\nAIM verifies credentials.\n' "$LINK" "$PHRASE" > "$T/doc.md"
expect_fail "the expansion only in an inline link title fails" "$T" first-use "doc.md:1"

T="$(new_tree title-only-reference)"
printf '[aim]: %s\n    "%s"\n\nSee [home][aim]. AIM verifies credentials.\n' \
    "$LINK" "$PHRASE" > "$T/doc.md"
expect_fail "the expansion only in a reference definition title fails" "$T" first-use "doc.md:2"

T="$(new_tree link-text-with-title)"
printf '[%s](%s "home")\n\nAIM verifies credentials.\n' "$PHRASE" "$LINK" > "$T/doc.md"
expect_pass "the expansion in link text counts when the link also has a title" "$T"

T="$(new_tree paragraph-break)"
printf 'OpenA2A\n\nAIM (Agent Identity Management) verifies.\n' > "$T/doc.md"
expect_fail "the phrase split by a paragraph break is not the expansion" "$T" first-use "doc.md:3"

T="$(new_tree paragraph-break-spaces)"
printf 'The platform is OpenA2A AIM (Agent \n  \nIdentity Management). AIM verifies.\n' > "$T/doc.md"
expect_fail "a line holding only spaces is a paragraph break too" "$T" first-use "doc.md:1"

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

T="$(new_tree trust-layer-descriptive)"
printf 'ATX adds a trust layer on top of agent identity.\n' > "$T/doc.md"
expect_fail "trust layer fails in a descriptive use as well" "$T" product-name "doc.md:1"
if grep -qF "is used as a name" "$OUT" || ! grep -qF "not used, even as a description" "$OUT"; then
    not_ok "the trust layer failure says the phrase is not used at all, not that it is a name" \
        "$(head -c 400 "$OUT" | tr '\n' ' ')"
else
    ok "the trust layer failure says the phrase is not used at all, not that it is a name"
fi

T="$(new_tree trust-layer-paragraphs)"
printf '## Trust\n\nLayer two of the stack is the wire format.\n' > "$T/doc.md"
expect_pass "trust and layer in separate paragraphs are not the phrase" "$T"

T="$(new_tree wai-aria)"
printf 'The browser extension follows WAI-ARIA for its warning banner.\n' > "$T/README.md"
expect_pass "WAI-ARIA, the accessibility specification, is allowed" "$T"

# --- reporting --------------------------------------------------------------

T="$(new_tree summary)"
mkdir -p "$T/errata"
printf '%s verifies.\n' "$PHRASE" > "$T/README.md"
printf 'The platform is OpenA2A AIM (Agent\nIdentity Management).\n' > "$T/core.md"
printf 'No component is named here.\n' > "$T/errata/notes.md"
run_check "$T"
if [ $? -eq 0 ] && grep -qF "naming ok: 3 Markdown file(s) checked, 2 use AIM and" "$OUT"; then
    ok "the summary counts the files checked and the files that use AIM"
else
    not_ok "the summary counts the files checked and the files that use AIM" \
        "$(head -c 400 "$OUT" | tr '\n' ' ')"
fi

T="$(new_tree not-utf8)"
printf 'Clean.\n' > "$T/README.md"
printf 'Line one.\ncaf\351 AIM\n' > "$T/doc.md"
expect_fail "a file that is not UTF-8 exits 1 naming the file and line" "$T" encoding "doc.md:2"
if grep -q "Traceback" "$OUT"; then
    not_ok "a file that is not UTF-8 is reported without a traceback" \
        "$(head -c 400 "$OUT" | tr '\n' ' ')"
else
    ok "a file that is not UTF-8 is reported without a traceback"
fi

T="$(new_tree many-failures)"
python3 -B -c "open('$T/doc.md', 'w').write('WAI-ARIA ARIA ' * 150000)"
STARTED=$(date +%s)
expect_fail "a 2 MB file with 150000 failures is reported" "$T" product-name "doc.md:1"
ELAPSED=$(( $(date +%s) - STARTED ))
if [ "$ELAPSED" -le 10 ]; then
    ok "a 2 MB file with 150000 failures is checked in under 10 s (took ${ELAPSED} s)"
else
    not_ok "a 2 MB file with 150000 failures is checked in under 10 s" "took ${ELAPSED} s"
fi
if [ "$(grep -c '\[product-name\]' "$OUT")" -eq 20 ] \
    && grep -qF "doc.md: 149980 more failure(s) in this file not shown" "$OUT"; then
    ok "failures past the first 20 in a file are counted, not listed"
else
    not_ok "failures past the first 20 in a file are counted, not listed" \
        "$(grep -c '\[product-name\]' "$OUT") listed; $(tail -c 200 "$OUT" | tr '\n' ' ')"
fi

# A long run of spaces where a phrase or a link title could continue is read once,
# not split every possible way when the next word or the title does not follow.
T="$(new_tree spaces-after-trust)"
python3 -B -c "open('$T/doc.md', 'w').write('trust' + ' ' * 200000 + 'x\n')"
expect_pass_within "200000 spaces after trust, with no layer following, are checked in under 10 s" \
    "$T" 10

T="$(new_tree spaces-after-openaa)"
python3 -B -c "open('$T/doc.md', 'w').write('OpenA2A' + ' ' * 200000 + 'x. $PHRASE verifies.\n')"
expect_pass_within "200000 spaces after OpenA2A ahead of the expansion are checked in under 10 s" \
    "$T" 10

T="$(new_tree spaces-after-link-paren)"
python3 -B -c "open('$T/doc.md', 'w').write('$PHRASE verifies. See [a](' + ' ' * 200000)"
expect_pass_within "200000 spaces after a link's opening parenthesis are checked in under 10 s" \
    "$T" 10

run_check "$REPO" --bogus
RC=$?
python3 -B "$REPO/scripts/check_naming.py" --help > "$TMP/help.txt" 2>&1
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
