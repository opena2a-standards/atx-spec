#!/usr/bin/env bash
# Tests for scripts/check_readme_lead.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree and asserted to exit 1 naming the file, the line and the rule; the
# delivered tree itself is asserted to exit 0. Shell rather than pytest so it
# runs with nothing installed: bash and python3 are all this needs.
#
#   bash scripts/test_readme_lead.sh
#
# Output is TAP-ish: one line per leaf test. Exit 0 when every test passes.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAV='> **specs** · [ATP](https://example.org/atp) · **ATX**'
DESC='Architecture specifications for the **ATX** credential format.'
TAB="$(printf '\t')"

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
    python3 -B "$REPO/scripts/check_readme_lead.py" --root "$1" > "$OUT" 2>&1
}

new_tree() {  # new_tree <name> <README text> -> path to a scratch tree holding that README.md
    mkdir -p "$TMP/$1"
    printf '%s' "$2" > "$TMP/$1/README.md"
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

expect_pass "the repository's own README.md passes" "$REPO"

# --- lead -------------------------------------------------------------------

T="$(new_tree plain "$NAV

# spec

$DESC

## Start here
")"
expect_pass "navigation line, title, one-sentence description and a section pass" "$T"

# The comment line stands alone between blank lines: counted as text, it would
# be a paragraph of its own and the description a second one.
T="$(new_tree badges "# spec

[![CI](https://example.org/ci.svg)](https://example.org/ci) ![License](https://example.org/l.svg)

<!-- one sentence only -->

$DESC

## Start here
")"
expect_pass "badge lines and a comment line do not count as paragraphs" "$T"

T="$(new_tree summary-paragraph "$NAV

# spec

$DESC

ATX is a signed credential. Local verification under 5ms.

## Start here
")"
expect_fail "a summary paragraph under the description fails at its first line" \
    "$T" lead "README.md:7"

T="$(new_tree two-sentences "# spec

$DESC It is analogous to a TLS certificate.

## Start here
")"
expect_fail "a second sentence appended to the description fails" \
    "$T" lead "README.md:3"

T="$(new_tree wrapped-second-sentence "# spec

Architecture specifications for the
**ATX** credential format. Ed25519
signatures are mandatory.

## Start here
")"
expect_fail "a second sentence starting on a continuation line is reported on that line" \
    "$T" lead "README.md:4"

T="$(new_tree wrapped-one-sentence "# spec

Architecture specifications for the **ATX**
credential format, version 1.1 of which is normative.

## Start here
")"
expect_pass "one sentence wrapped across a soft line break, with a decimal in it, passes" "$T"

# The fenced block comes before the description: if its heading ended the lead,
# the lead would be the fence line alone and the README would pass. Read as a
# code block, the block is the lead's first paragraph and the description on
# line 7 its second.
T="$(new_tree fenced-heading "# spec

\`\`\`sh
## not a heading
\`\`\`

$DESC

## Start here
")"
expect_fail "a heading inside a fenced code block does not end the lead" \
    "$T" lead "README.md:7"

# A closing fence longer than the opening one closes the block: left open, the
# block would hold the section heading and the README would fail as [missing].
T="$(new_tree fence-longer-close "# spec

\`\`\`sh
## not a heading
\`\`\`\`

$DESC

## Start here
")"
expect_fail "a closing fence longer than the opening one closes the block" \
    "$T" lead "README.md:7"

T="$(new_tree fence-indented-three "# spec

   \`\`\`sh
## not a heading
   \`\`\`$TAB

$DESC

## Start here
")"
expect_fail "fences indented three spaces open and close a block, the closing one followed by a tab" \
    "$T" lead "README.md:7"

# Each block below stands above the title and ends on a line that closes it.
# Were a line inside it taken as the closing fence, that last line would open a
# new block running to the end of the file, and the title would be missed.
T="$(new_tree fence-other-char "\`\`\`text
~~~
\`\`\`

# spec

$DESC

## Start here
")"
expect_pass "a tilde fence line does not close a backtick block" "$T"

T="$(new_tree fence-shorter "\`\`\`\`md
\`\`\`
\`\`\`\`

# spec

$DESC

## Start here
")"
expect_pass "a fence shorter than the opening one does not close the block" "$T"

T="$(new_tree fence-info-string "\`\`\`text
\`\`\`sh
\`\`\`

# spec

$DESC

## Start here
")"
expect_pass "a fence line with an info string does not close the block" "$T"

T="$(new_tree fence-indented-close "\`\`\`
    \`\`\`
\`\`\`

# spec

$DESC

## Start here
")"
expect_pass "a fence line indented four spaces does not close the block" "$T"

# Read as a fence, the first line would open a block running to the end of the
# file, and the title would be missed.
T="$(new_tree fence-indented-open "    \`\`\`

# spec

$DESC

## Start here
")"
expect_pass "a fence line indented four spaces does not open a block" "$T"

T="$(new_tree fence-tab-open "$TAB\`\`\`

# spec

$DESC

## Start here
")"
expect_pass "a fence line indented by a tab does not open a block" "$T"

T="$(new_tree fence-backtick-info "\`\`\`a\`b

# spec

$DESC

## Start here
")"
expect_pass "a backtick run whose info string holds a backtick does not open a block" "$T"

# --- HTML blocks ------------------------------------------------------------

# A block opened by a block-level tag runs to the next blank line, so the "# "
# line under it renders as text and the README has no title.
T="$(new_tree html-block-tag "<div align=\"center\">
# spec

$DESC

## Start here
")"
expect_fail "a title directly under a block-level tag is not the title" \
    "$T" missing "README.md:1"

T="$(new_tree html-block-tag-blank "<div align=\"center\">

# spec

$DESC

## Start here
")"
expect_pass "a blank line closes a block opened by a block-level tag" "$T"

T="$(new_tree html-block-tag-section "# spec

$DESC

<DETAILS>
## Start here
")"
expect_fail "a section heading directly under an upper-case block-level tag is not the section heading" \
    "$T" missing "README.md:1"

T="$(new_tree html-comment "<!--
# spec
-->

$DESC

## Start here
")"
expect_fail "a title inside a comment that spans lines is not the title" \
    "$T" missing "README.md:1"

# Were the comment's closing searched for only below its opening line, the
# block would run to the end of the file and the title would be missed.
T="$(new_tree html-comment-one-line "<!-- navigation above -->
# spec

$DESC

## Start here
")"
expect_pass "a comment that closes on its opening line holds no line below it" "$T"

T="$(new_tree html-pre-blank "<pre>

# spec
</pre>

$DESC

## Start here
")"
expect_fail "a blank line does not close a block opened by <pre>, so the title before </pre> is inside it" \
    "$T" missing "README.md:1"

T="$(new_tree html-lone-tag "<a href=\"https://example.org/atx\">
# spec

$DESC

## Start here
")"
expect_fail "a title directly under a line holding only an open tag is not the title" \
    "$T" missing "README.md:1"

# Under the navigation line the tag continues its paragraph, and the "# " line
# below interrupts that paragraph as a heading.
T="$(new_tree html-lone-tag-under-text "$NAV
<br>
# spec

$DESC

## Start here
")"
expect_pass "a line holding only a tag opens no block directly under a line of text" "$T"

T="$(new_tree html-inline-tag "<span>ATX</span> specifications
# spec

$DESC

## Start here
")"
expect_pass "a line with text after its tag opens no block" "$T"

T="$(new_tree html-indented "    <div>
# spec

$DESC

## Start here
")"
expect_pass "a tag indented four spaces opens no block" "$T"

# Read as a fence, the second line would open a code block running to the end
# of the file, and the title would be missed.
T="$(new_tree html-fence-inside "<div>
\`\`\`

# spec

$DESC

## Start here
")"
expect_pass "a fence line inside an HTML block does not open a code block" "$T"

# --- missing ----------------------------------------------------------------

T="$(new_tree no-title "$DESC

## Start here
")"
expect_fail "a README with no title fails instead of passing vacuously" \
    "$T" missing "README.md:1"

T="$(new_tree no-section "# spec

$DESC
")"
expect_fail "a README with no section heading after the title fails" \
    "$T" missing "README.md:1"

T="$(new_tree no-description "# spec

## Start here
")"
expect_fail "a README with nothing between the title and the first section fails" \
    "$T" missing "README.md:1"

mkdir -p "$TMP/no-readme"
expect_fail "a tree with no README.md fails instead of passing vacuously" \
    "$TMP/no-readme" missing "README.md:1"

# --- encoding ---------------------------------------------------------------

T="$(new_tree latin1 "# spec

")"
printf 'Specifications for the caf\351 format.\n\n## Start here\n' >> "$T/README.md"
expect_fail "a README that is not UTF-8 fails" "$T" encoding "README.md:3"

# --- summary ----------------------------------------------------------------

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d of %d test(s) failed\n' "$FAILED" "$COUNT"
    exit 1
fi
printf '# %d test(s) passed\n' "$COUNT"
