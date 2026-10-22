#!/usr/bin/env bash
# Tests for scripts/check_review_marker.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree and asserted to exit 1 naming the place and the rule, among them the
# sentence the file used to open with; the delivered tree is asserted to exit 0.
# Shell rather than pytest so it runs with nothing installed: bash and python3
# are all this needs.
#
#   bash scripts/test_review_marker.sh
#
# Output is TAP-ish: one line per leaf test. Exit 0 when every test passes.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARKER=".pre-push-review-not-required"

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
    python3 -B "$REPO/scripts/check_review_marker.py" --root "$1" > "$OUT" 2>&1
}

new_dir() {  # new_dir <name> -> path to an empty scratch directory
    mkdir -p "$TMP/$1"
    printf '%s' "$TMP/$1"
}

expect_fail() {  # expect_fail <leaf name> <root> <where> <rule> [<detail>]
    local name="$1" root="$2" where="$3" rule="$4" detail="${5-}" rc
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
    if [ -n "$detail" ] && ! grep -qF -- "$detail" "$OUT"; then
        not_ok "$name" "exit 1 but '$detail' not reported: $(head -c 400 "$OUT" | tr '\n' ' ')"
        return
    fi
    ok "$name"
}

expect_pass() {  # expect_pass <leaf name> <root> [<detail>]
    local name="$1" detail="${3-}" rc
    run_check "$2"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        not_ok "$name" "expected exit 0, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
        return
    fi
    if [ -n "$detail" ] && ! grep -qF -- "$detail" "$OUT"; then
        not_ok "$name" "exit 0 but '$detail' not reported: $(head -c 400 "$OUT" | tr '\n' ' ')"
        return
    fi
    ok "$name"
}

write_marker() {  # write_marker <root> <text>
    printf '%s\n' "$2" > "$1/$MARKER"
}

add_scripts() {  # add_scripts <root> <path under scripts/> [...]
    local root="$1" rel
    shift
    for rel in "$@"; do
        mkdir -p "$(dirname "$root/scripts/$rel")"
        printf '# scratch\n' > "$root/scripts/$rel"
    done
}

# new_tree <name> -> a scratch tree whose scripts/ holds check_a.py and test_a.sh
new_tree() {
    local root
    root="$(new_dir "$1")"
    add_scripts "$root" check_a.py test_a.sh
    printf '%s' "$root"
}

# Names both scripts new_tree adds.
NAMES='Scripts: `scripts/check_*.py` and `scripts/test_*.sh`.'

# --- the delivered tree -----------------------------------------------------

expect_pass "the delivered $MARKER agrees with the tree" "$REPO" "review marker ok"

# --- the sentence the file used to open with ----------------------------------

T="$(new_tree previous)"
write_marker "$T" 'Spec/docs-only repository. No CLI, build, test suite, or runnable artifacts.'
expect_fail "the previous opening denies a test suite while scripts/ holds files" \
    "$T" "$MARKER:1" denied "denies 'test suite'"
expect_fail "a script no backticked path names fails as unnamed" \
    "$T" "scripts/check_a.py" unnamed

# --- [unnamed] --------------------------------------------------------------

T="$(new_tree globs)"
write_marker "$T" "$NAMES"
expect_pass "a glob names every script it matches" "$T"

T="$(new_tree literal)"
write_marker "$T" 'Run `scripts/check_a.py` and `scripts/test_a.sh`.'
expect_pass "a literal path names the script it matches" "$T"

T="$(new_tree dir-only)"
write_marker "$T" 'The scripts live under `scripts/`.'
expect_fail "a directory path names none of the files in it" \
    "$T" "scripts/check_a.py" unnamed

T="$(new_tree dir-exists)"
write_marker "$T" "$NAMES"' They live under `scripts/`.'
expect_pass "a directory path that exists is not unmatched" "$T"

T="$(new_tree dotfiles)"
add_scripts "$T" .keep lib/util.py
write_marker "$T" "$NAMES"
expect_pass "a dotfile or a file in a subdirectory of scripts/ needs no name" "$T"

T="$(new_tree case)"
write_marker "$T" 'Run `Scripts/check_a.py` and `scripts/test_a.sh`.'
expect_fail "a name is matched case and all" \
    "$T" "$MARKER:1" unmatched "Scripts/check_a.py"
expect_fail "a script named only in another case is unnamed" \
    "$T" "scripts/check_a.py" unnamed

# --- [unmatched] ------------------------------------------------------------

T="$(new_tree gone)"
write_marker "$T" "$NAMES"$'\n\n''- `scripts/check_gone.py` checks nothing now.'
expect_fail "a path that matches nothing fails as unmatched on its own line" \
    "$T" "$MARKER:3" unmatched "scripts/check_gone.py"

T="$(new_tree glob-none)"
write_marker "$T" "$NAMES"' Linters: `scripts/lint_*.py`.'
expect_fail "a glob that matches nothing fails as unmatched" \
    "$T" "$MARKER:1" unmatched "scripts/lint_*.py"

T="$(new_tree glob-depth)"
add_scripts "$T" lib/notes.txt
write_marker "$T" "$NAMES"' Notes: `scripts/*.txt`.'
expect_fail "a * matches within one part, never across a /" \
    "$T" "$MARKER:1" unmatched "scripts/*.txt"

T="$(new_tree outside)"
mkdir -p "$TMP/outside"
printf '# scratch\n' > "$TMP/outside/check_a.py"
write_marker "$T" "$NAMES"' See `../outside/check_a.py`.'
expect_fail "a path with a .. part fails as unmatched although the file exists" \
    "$T" "$MARKER:1" unmatched "leaves the tree"

T="$(new_tree absolute)"
write_marker "$T" "$NAMES"" See \`$T/scripts/check_a.py\`."
expect_fail "an absolute path fails as unmatched although the file exists" \
    "$T" "$MARKER:1" unmatched "leaves the tree"

T="$(new_tree tree-root)"
write_marker "$T" "$NAMES"' Run them from `./`.'
expect_pass "a path naming the tree itself is not unmatched" "$T"

T="$(new_tree not-paths)"
write_marker "$T" "$NAMES"' Run `python3 scripts/check_gone.py`, `bash` or see `https://example.org/a/b`.'
expect_pass "a span with whitespace, a URL or a span with no / is not read as a path" "$T"

# --- [denied] ---------------------------------------------------------------

T="$(new_tree no-tests)"
write_marker "$T" "$NAMES"' There are no tests here.'
expect_fail "no tests is a denial" "$T" "$MARKER:1" denied "denies 'tests'"

T="$(new_tree without)"
write_marker "$T" "$NAMES"' It ships without scripts.'
expect_fail "without scripts is a denial" "$T" "$MARKER:1" denied "denies 'scripts'"

T="$(new_tree neither)"
write_marker "$T" "$NAMES"' There are neither checks nor tests.'
expect_fail "neither checks nor tests is a denial" "$T" "$MARKER:1" denied "denies 'checks'"

T="$(new_tree runnable)"
write_marker "$T" "$NAMES"' There are no runnable files and no executables.'
expect_fail "no runnable files is a denial" "$T" "$MARKER:1" denied "denies 'runnable'"

T="$(new_tree wrapped)"
write_marker "$T" "$NAMES"$'\n''There are no'$'\n''tests here.'
expect_fail "a denial wrapped across lines is reported on the line of its negation" \
    "$T" "$MARKER:2" denied "denies 'tests'"

T="$(new_tree singular)"
write_marker "$T" "$NAMES"' No test needs network access.'
expect_pass "no test followed by a verb is not a denial" "$T"

T="$(new_tree later-clause)"
write_marker "$T" "$NAMES"' There is no build; the tests run with bash.'
expect_pass "a term in a later clause is not in the list" "$T"

T="$(new_tree parenthesis)"
write_marker "$T" "$NAMES"' There is no package (the tests run from a clone).'
expect_pass "a term inside a parenthesis is not in the list" "$T"

T="$(new_tree list-tail)"
write_marker "$T" "$NAMES"' There is no package or build output to install, so the tests run from a clone.'
expect_pass "a list item that does not begin with a term is not a denial" "$T"

T="$(new_tree code-span)"
write_marker "$T" "$NAMES"' Do not pass `no tests` or `--no-scripts` to it.'
expect_pass "a backticked span is not read as words" "$T"

T="$(new_dir empty-scripts)"
write_marker "$T" 'There are no tests or scripts.'
expect_pass "a denial passes while scripts/ holds no file" "$T"

# --- the file itself --------------------------------------------------------

T="$(new_tree absent)"
expect_pass "a tree without the file passes" "$T" "nothing to check"

T="$(new_tree directory)"
mkdir -p "$T/$MARKER"
expect_fail "a directory in place of the file fails as unreadable" \
    "$T" "$MARKER" unreadable "not a regular file"

T="$(new_tree not-utf8)"
printf 'No tests \377\376\n' > "$T/$MARKER"
expect_fail "a file that is not UTF-8 text fails as unreadable" \
    "$T" "$MARKER" unreadable "not UTF-8 text"

# --- usage ------------------------------------------------------------------

python3 -B "$REPO/scripts/check_review_marker.py" --root "$TMP/no-such-tree" > "$OUT" 2>&1
rc=$?
if [ "$rc" -eq 2 ]; then
    ok "a --root that is not a directory is a usage error"
else
    not_ok "a --root that is not a directory is a usage error" \
        "expected exit 2, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
fi

# --- summary ----------------------------------------------------------------

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d of %d test(s) failed\n' "$FAILED" "$COUNT"
    exit 1
fi
printf '# %d test(s) passed\n' "$COUNT"
