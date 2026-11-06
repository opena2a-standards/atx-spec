#!/usr/bin/env bash
# Tests for scripts/check_a2a_citations.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree and asserted to exit 1 naming the file, the line and the rule; the
# delivered tree itself is asserted to exit 0. Shell rather than pytest so it
# runs with nothing installed: bash and python3 are all this needs.
#
#   bash scripts/test_a2a_citations.sh
#
# Output is TAP-ish: one line per leaf test. Exit 0 when every test passes.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
OUT="$TMP/out.txt"

COUNT=0
FAILED=0
SKIPPED=0

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

skip() {  # skip <leaf test name> <why>
    COUNT=$((COUNT + 1))
    SKIPPED=$((SKIPPED + 1))
    printf 'ok %d - %s # SKIP %s\n' "$COUNT" "$1" "$2"
}

run_check() {  # run_check <root>
    python3 -B "$REPO/scripts/check_a2a_citations.py" --root "$1" > "$OUT" 2>&1
}

new_tree() {  # new_tree <name> -> path to an empty scratch tree
    mkdir -p "$TMP/$1"
    printf '%s' "$TMP/$1"
}

expect_fail() {  # expect_fail <leaf name> <root> <file:line> [rule, default duplicate]
    local name="$1" root="$2" where="$3" rule="${4:-duplicate}" rc
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
    if grep -q 'Traceback' "$OUT"; then
        not_ok "$name" "exit 1 with a traceback: $(head -c 400 "$OUT" | tr '\n' ' ')"
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

expect_count() {  # expect_count <leaf name> <root> <number of [duplicate] failures>
    local name="$1" root="$2" want="$3" rc got
    run_check "$root"
    rc=$?
    got="$(grep -c '\[duplicate\]' "$OUT")"
    if [ "$rc" -eq 1 ] && [ "$got" -eq "$want" ]; then
        ok "$name"
    else
        not_ok "$name" "expected exit 1 and $want [duplicate] line(s), got exit $rc and $got: $(head -c 400 "$OUT" | tr '\n' ' ')"
    fi
}

# --- the delivered tree -----------------------------------------------------

expect_pass "the repository's own Markdown passes" "$REPO"

# --- duplicate --------------------------------------------------------------

T="$(new_tree section-2)"
cat > "$T/core.md" <<'EOF'
## 2. ATP: the protocol layer

ATP is the standards play. ATX is the wedge. Our open A2A pull request #1850, a roadmap document, links ATP and ATX only as a spec set tracked separately. The coordination issue we opened for that set, #1876, was closed as not planned on 2026-06-15. We intend to take ATP to the IETF.
EOF
expect_fail "the section 2 sentence that names #1876 alone as the coordination issue fails" \
    "$T" "core.md:3"

T="$(new_tree no-original)"
printf 'We closed #1876 on 2026-06-15 as a duplicate.\n' > "$T/core.md"
expect_fail "a paragraph that says duplicate but does not cite #1885 fails" "$T" "core.md:1"

T="$(new_tree no-word)"
printf 'The coordination issue #1876 was closed on 2026-06-15; the thread is on #1885.\n' > "$T/core.md"
expect_fail "a paragraph that cites #1885 but does not say duplicate fails" "$T" "core.md:1"

T="$(new_tree duplication)"
printf 'The closure of #1876 avoided a duplication with #1885.\n' > "$T/core.md"
expect_fail "duplication is not one of the words read as duplicate" "$T" "core.md:1"

T="$(new_tree next-paragraph)"
printf 'The coordination issue #1876 was closed.\n\nIt was a duplicate of #1885.\n' > "$T/README.md"
expect_fail "#1885 and duplicate past a blank line do not count" "$T" "README.md:1"

T="$(new_tree blank-with-spaces)"
printf 'The coordination issue #1876 was closed.\n \t\nIt was a duplicate of #1885.\n' > "$T/README.md"
expect_fail "a line of spaces and tabs is a blank line" "$T" "README.md:1"

T="$(new_tree crlf)"
printf 'The coordination issue #1876 was closed.\r\n\r\nIt was a duplicate of #1885.\r\n' > "$T/README.md"
expect_fail "a blank line ends a paragraph in a file with CRLF line ends" "$T" "README.md:1"

T="$(new_tree citation-line)"
printf 'Intro.\n\nThe A2A project has two\ncoordination issues, and\nA2A#1876 was closed.\n' > "$T/core.md"
expect_fail "the failure names the line of the citation, not the first line of the paragraph" \
    "$T" "core.md:5"

T="$(new_tree two-paragraphs)"
printf '#1876 was closed.\n\nAgain: #1876 was closed.\n' > "$T/core.md"
expect_fail "each failing paragraph is reported: the first" "$T" "core.md:1"
expect_fail "each failing paragraph is reported: the second" "$T" "core.md:3"

T="$(new_tree one-per-paragraph)"
printf 'The coordination issue\n#1876 was closed.\nSee [#1876](https://github.com/a2aproject/A2A/issues/1876).\n' > "$T/core.md"
expect_count "a paragraph that cites #1876 three times is reported once" "$T" 1
expect_fail "a paragraph is reported at its first citation of #1876" "$T" "core.md:2"

N=0
for form in '#1876' '(#1876)' 'A2A#1876' 'a2a#1876' 'a2aproject/A2A#1876' 'A2AProject/a2a#1876' \
    'https://github.com/a2aproject/A2A/issues/1876' \
    'https://github.com/a2aproject/A2A/pull/1876' \
    'https://GitHub.com/A2AProject/a2a/issues/1876#issuecomment-1'; do
    N=$((N + 1))
    T="$(new_tree "form-$N")"
    printf 'The coordination issue %s was closed.\n' "$form" > "$T/core.md"
    expect_fail "the citation form $form is read" "$T" "core.md:1"
done

N=0
for form in 'A2A#1885' 'a2aproject/A2A#1885' 'https://github.com/a2aproject/A2A/issues/1885'; do
    N=$((N + 1))
    T="$(new_tree "original-form-$N")"
    printf 'We closed #1876 as a duplicate of %s.\n' "$form" > "$T/core.md"
    expect_pass "#1885 cited as $form counts" "$T"
done

T="$(new_tree not-citations)"
printf 'See #18760, #1876a, #1876_, #187, page#1876, 5#1876, &#1876;, /#1876, ##1876, issue_#1876 and opena2a/A2A#1876.\n' > "$T/core.md"
expect_pass "#18760, #1876a, #1876_, #187 and a # after a letter, digit, _, /, # or & are not citations" "$T"

T="$(new_tree fixed)"
printf 'We opened two coordination issues for that set. We closed #1876 on 2026-06-15 as a duplicate of #1885, and #1885 was converted to a discussion on 2026-06-23.\n' > "$T/core.md"
expect_pass "a paragraph that cites #1876, cites #1885 and says duplicate passes" "$T"

T="$(new_tree wrapped)"
printf 'Intro.\n\nWe closed\n#1876 on 2026-06-15 as a\nDUPLICATE of #1885.\n' > "$T/core.md"
expect_pass "a paragraph that wraps across lines and says duplicate in capitals passes" "$T"

T="$(new_tree duplicated)"
printf '#1876 duplicated #1885, so it was closed.\n' > "$T/core.md"
expect_pass "duplicated counts as saying duplicate" "$T"

T="$(new_tree list)"
printf 'Intro.\n\n- #1876 was closed on 2026-06-15.\n- It duplicates #1885.\n' > "$T/core.md"
expect_pass "a list with no blank line in it is one paragraph" "$T"

T="$(new_tree table)"
printf '| Issue | Closed |\n|---|---|\n| #1876 | 2026-06-15 |\n| #1885 | 2026-06-23; the issue in the row above was a duplicate of it |\n' > "$T/core.md"
expect_pass "a table with no blank line in it is one paragraph" "$T"

T="$(new_tree duplicate-of-something-else)"
printf '#1876 was closed. #1885 lists the catalogue, and the catalogue is a duplicate of the roadmap.\n' > "$T/core.md"
expect_pass "a paragraph that cites both issues and says duplicate of something else passes" "$T"

T="$(new_tree original-only)"
printf 'The coordination issue we opened for that set, #1885, was converted to a discussion on 2026-06-23.\n' > "$T/core.md"
expect_pass "a paragraph that cites #1885 and not #1876 passes" "$T"

T="$(new_tree history)"
mkdir -p "$T/errata"
printf 'Clean.\n' > "$T/core.md"
printf -- '- The coordination issue we opened for that set, #1876, was closed as not planned on 2026-06-15.\n' > "$T/CHANGELOG.md"
printf 'oldText: |\n  The coordination issue we opened for that set, #1876, was closed as not planned.\n' > "$T/errata/ATX-E-0001.md"
expect_pass "CHANGELOG.md and errata, which quote earlier text, are not checked" "$T"

T="$(new_tree nested)"
mkdir -p "$T/docs"
printf 'Clean.\n' > "$T/README.md"
printf 'Line one.\nThe coordination issue, #1876, was closed.\n' > "$T/docs/notes.md"
expect_fail "a Markdown file in a subdirectory is checked" "$T" "docs/notes.md:2"

T="$(new_tree skipped-dirs)"
mkdir -p "$T/.suite" "$T/node_modules/pkg"
printf 'Clean.\n' > "$T/README.md"
printf '#1876 was closed.\n' > "$T/.suite/README.md"
printf '#1876 was closed.\n' > "$T/node_modules/pkg/README.md"
expect_pass "hidden directories and node_modules are not checked" "$T"

T="$(new_tree md-directory)"
mkdir -p "$T/notes.md"
printf 'Clean.\n' > "$T/README.md"
expect_pass "a directory whose name ends in .md is not read" "$T"

# --- files that cannot be checked -------------------------------------------

T="$(new_tree not-utf8)"
printf 'Clean.\n' > "$T/README.md"
printf 'Caf\351 #1876.\n' > "$T/core.md"
expect_fail "a file that is not UTF-8 fails as [encoding], with no traceback" "$T" "core.md" encoding

T="$(new_tree unreadable)"
printf 'Clean.\n' > "$T/README.md"
printf '#1876 was closed as a duplicate of #1885.\n' > "$T/core.md"
chmod 000 "$T/core.md"
if [ -r "$T/core.md" ]; then
    skip "a file that cannot be read fails as [read], with no traceback" \
        "the file stays readable after chmod 000, as it does for root"
else
    expect_fail "a file that cannot be read fails as [read], with no traceback" "$T" "core.md" read
fi
chmod 644 "$T/core.md"

T="$(new_tree empty)"
run_check "$T"
rc=$?
if [ "$rc" -eq 1 ] && grep -qF "refusing to pass vacuously" "$OUT"; then
    ok "a tree with no Markdown file fails rather than passing vacuously"
else
    not_ok "a tree with no Markdown file fails rather than passing vacuously" \
        "expected exit 1 and a refusal, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
fi

python3 -B "$REPO/scripts/check_a2a_citations.py" --no-such-option > "$OUT" 2>&1
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
printf '# %d test(s) passed, %d skipped\n' "$((COUNT - SKIPPED))" "$SKIPPED"
