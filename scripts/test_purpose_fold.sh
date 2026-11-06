#!/usr/bin/env bash
# Tests for scripts/check_purpose_fold.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree and asserted to exit 1 naming the file, the line and the rule; the
# delivered tree itself is asserted to exit 0. Shell rather than pytest so it
# runs with nothing installed: bash and python3 are all this needs.
#
#   bash scripts/test_purpose_fold.sh
#
# Output is TAP-ish: one line per leaf test. Exit 0 when every test passes.
# Characters outside ASCII are written as octal UTF-8 bytes so the file runs
# under bash 3.2: U+212A KELVIN SIGN is \342\204\252 and U+017F LATIN SMALL
# LETTER LONG S is \305\277.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
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
    local root="$1"
    shift
    python3 -B "$REPO/scripts/check_purpose_fold.py" --root "$root" "$@" > "$OUT" 2>&1
}

new_tree() {  # new_tree <name> -> path to an empty scratch tree
    mkdir -p "$TMP/$1"
    printf '%s' "$TMP/$1"
}

expect_pass() {  # expect_pass <leaf name> <root> [extra args...]
    local name="$1" root="$2" rc
    shift 2
    run_check "$root" "$@"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        ok "$name"
    else
        not_ok "$name" "expected exit 0, got $rc: $(head -c 600 "$OUT" | tr '\n' ' ')"
    fi
}

expect_fail() {  # expect_fail <leaf name> <root> <where> <rule> [extra args...]
    local name="$1" root="$2" where="$3" rule="$4" rc
    shift 4
    run_check "$root" "$@"
    rc=$?
    if [ "$rc" -ne 1 ]; then
        not_ok "$name" "expected exit 1, got $rc: $(head -c 600 "$OUT" | tr '\n' ' ')"
        return
    fi
    if ! grep -qF -- "$where [$rule]" "$OUT"; then
        not_ok "$name" "expected '$where [$rule]' in: $(head -c 600 "$OUT" | tr '\n' ' ')"
        return
    fi
    ok "$name"
}

# A core.md whose fold paragraph starts on line 3 and names the ASCII fold and
# the two folds outside ASCII, and whose restatement names them too.
GOOD_RULE='Inside `declaredPurpose` the strict parse also treats as a duplicate member
two members whose names are equal once each ASCII letter `A` to `Z` in them is
replaced by its lower-case letter, each U+212A KELVIN SIGN by `k` and each
U+017F LATIN SMALL LETTER LONG S by `s`.'

good_core() {  # good_core <tree>
    printf '# Core\n\n%s\n\nA pair inside `declaredPurpose` equal under the fold of the rule above.\n' \
        "$GOOD_RULE" > "$1/core.md"
}

# A Go source whose foldKey has the given non-ASCII case lines.
go_suite() {  # go_suite <tree> <case lines (printf format)>
    mkdir -p "$1/verifiers/go/verifier"
    printf 'package verifier\n\nfunc foldKey(s string) string {\n\tfor _, r := range s {\n\t\tswitch {\n\t\tcase '"'"'A'"'"' <= r && r <= '"'"'Z'"'"':\n\t\t\tb.WriteRune(r + ('"'"'a'"'"' - '"'"'A'"'"'))\n'"$2"'\t\t}\n\t}\n}\n' \
        > "$1/verifiers/go/verifier/verify.go"
}

KELVIN_CASE="\t\tcase r == '\342\204\252': // Kelvin sign -> k\n\t\t\tb.WriteRune('k')\n"
LONGS_CASE="\t\tcase r == '\305\277': // long s -> s\n\t\t\tb.WriteRune('s')\n"
# A made-up third fold, written as a Go \u escape, that core.md does not name.
MICRO_CASE="\t\tcase r == '\\\\u00b5': // made-up fold -> m\n\t\t\tb.WriteRune('m')\n"

# --- the delivered tree -----------------------------------------------------

expect_pass "the delivered core.md passes" "$REPO"

# --- passing shapes ---------------------------------------------------------

T="$(new_tree good)"
good_core "$T"
expect_pass "a fold paragraph naming A to Z, U+212A to k and U+017F to s passes" "$T"

T="$(new_tree lowerhex)"
printf '# Core\n\nInside `declaredPurpose` a duplicate member is two names equal once `A` to `Z`\nare lower-cased, u+212a is replaced by `k` and u+017f by `s`.\n' > "$T/core.md"
expect_pass "a code point written with lower-case hex digits is named" "$T"

S="$(new_tree suite-same)"
go_suite "$S" "$KELVIN_CASE$LONGS_CASE"
T="$(new_tree suite-same-core)"
good_core "$T"
expect_pass "--suite: a foldKey with the Kelvin sign and the long s passes" "$T" --suite "$S"

# --- failing shapes ---------------------------------------------------------

T="$(new_tree ascii-only-rule)"
printf '# Core\n\nInside `declaredPurpose` the strict parse also treats as a duplicate member\ntwo members whose names are equal once each ASCII letter `A` to `Z` in them is\nreplaced by its lower-case letter.\n' > "$T/core.md"
expect_fail "a fold paragraph that names only the ASCII fold fails" \
    "$T" "core.md:3" "unnamed"
if grep -qF "U+212A" "$OUT" && grep -qF "U+017F" "$OUT"; then
    ok "the [unnamed] failures name both code points"
else
    not_ok "the [unnamed] failures name both code points" "$(head -c 600 "$OUT" | tr '\n' ' ')"
fi

T="$(new_tree ascii-only-restatement)"
good_core "$T"
printf '\nA verifier rejects a pair of members inside `declaredPurpose` whose names differ only\n  in ASCII letter case.\n' >> "$T/core.md"
expect_fail "a restatement saying 'differ only in ASCII letter case' fails" \
    "$T" "core.md:10" "ascii-only"

T="$(new_tree missing)"
printf '# Core\n\nNothing about the purpose object here.\n' > "$T/core.md"
expect_fail "a core.md without the fold paragraph fails" "$T" "core.md" "missing"

T="$(new_tree no-ascii)"
printf '# Core\n\nInside `declaredPurpose` a duplicate member is two names equal once U+212A is\nreplaced by `k` and U+017F by `s`.\n' > "$T/core.md"
expect_fail "a fold paragraph that does not say A to Z fails" "$T" "core.md:3" "ascii"

T="$(new_tree far-letter)"
printf '# Core\n\nInside `declaredPurpose` a duplicate member is two names equal once `A` to `Z`\nare lower-cased, U+017F is replaced by `s`, and U+212A is replaced by the letter\nthat this sentence, which runs on for well over eighty characters, names as `k`.\n' > "$T/core.md"
expect_fail "a letter more than 80 characters after its code point does not count" \
    "$T" "core.md:3" "unnamed"

T="$(new_tree prefix)"
printf '# Core\n\nInside `declaredPurpose` a duplicate member is two names equal once `A` to `Z`\nare lower-cased, U+212AB is replaced by `k` and U+017F by `s`.\n' > "$T/core.md"
expect_fail "a longer code point that starts with 212A does not name U+212A" \
    "$T" "core.md:3" "unnamed"

S="$(new_tree suite-more)"
go_suite "$S" "$KELVIN_CASE$LONGS_CASE$MICRO_CASE"
T="$(new_tree suite-more-core)"
good_core "$T"
expect_fail "--suite: a case r == '<rune>': row with b.WriteRune('<letter>') that core.md does not name fails" \
    "$T" "core.md:3" "unnamed" --suite "$S"
if grep -qF "U+00B5" "$OUT"; then
    ok "--suite: the [unnamed] failure names the added code point"
else
    not_ok "--suite: the [unnamed] failure names the added code point" "$(head -c 600 "$OUT" | tr '\n' ' ')"
fi

S="$(new_tree suite-none)"
mkdir -p "$S/verifiers/go/verifier"
printf 'package verifier\n' > "$S/verifiers/go/verifier/verify.go"
T="$(new_tree suite-none-core)"
good_core "$T"
expect_fail "--suite: a verify.go without foldKey fails" "$T" "" "suite" --suite "$S"

S="$(new_tree suite-ascii)"
go_suite "$S" ""
expect_fail "--suite: a foldKey with no fold outside ASCII fails rather than passing vacuously" \
    "$T" "" "suite" --suite "$S"

expect_fail "--suite: a directory that is no checkout fails" "$T" "" "suite" --suite "$TMP/no-such-dir"

T="$(new_tree no-core)"
expect_fail "a tree without core.md fails" "$T" "core.md" "read"

T="$(new_tree latin1)"
printf '# Core\n\n\377\n' > "$T/core.md"
expect_fail "a core.md that is not UTF-8 fails" "$T" "core.md" "encoding"

python3 -B "$REPO/scripts/check_purpose_fold.py" --no-such-option > "$OUT" 2>&1
rc=$?
if [ "$rc" -eq 2 ]; then
    ok "an unknown option is a usage error, exit 2"
else
    not_ok "an unknown option is a usage error, exit 2" \
        "expected exit 2, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
fi

# --- summary ----------------------------------------------------------------

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d of %d test(s) failed\n' "$FAILED" "$COUNT"
    exit 1
fi
printf '# %d test(s) passed\n' "$COUNT"
