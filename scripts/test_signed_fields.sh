#!/usr/bin/env bash
# Tests for scripts/check_signed_fields.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree and asserted to exit 1 naming the file, the line and the rule; the
# delivered tree itself is asserted to exit 0. Shell rather than pytest so it
# runs with nothing installed: bash and python3 are all this needs.
#
#   bash scripts/test_signed_fields.sh
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
    python3 -B "$REPO/scripts/check_signed_fields.py" --root "$1" > "$OUT" 2>&1
}

run_check_within() {  # run_check_within <seconds> <root>: exit 124 when it takes longer
    python3 -B - "$1" "$REPO/scripts/check_signed_fields.py" "$2" > "$OUT" 2>&1 <<'PYEOF'
import subprocess, sys
limit, script, root = float(sys.argv[1]), sys.argv[2], sys.argv[3]
try:
    sys.exit(subprocess.run([sys.executable, "-B", script, "--root", root], timeout=limit).returncode)
except subprocess.TimeoutExpired:
    print(f"still running after {limit:g} s")
    sys.exit(124)
PYEOF
}

new_tree() {  # new_tree <name> -> path to an empty scratch tree
    mkdir -p "$TMP/$1"
    printf '%s' "$TMP/$1"
}

expect_fail() {  # expect_fail <leaf name> <root> <file:line> [rule, default level-lowered]
    local name="$1" root="$2" where="$3" rule="${4:-level-lowered}" rc
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

# --- level-lowered ----------------------------------------------------------

T="$(new_tree partition)"
cat > "$T/scalability.md" <<'EOF'
### 9.2 Federation node partition

* The partitioned node continues operating for its local population.
* Cross node cosignatures degrade to "unverified by root". Trust level 4 requests fall back to trust level 3.
EOF
expect_fail "a partition that has trust level 4 fall back to trust level 3 fails" "$T" "scalability.md:4"

T="$(new_tree conditional-row)"
cat > "$T/sovereign-federation.md" <<'EOF'
| State | Behavior |
|---|---|
| Allowed | ATX issued by this authority is honored at the trust level the credential specifies. |
| Conditional | ATX is honored but trust level is capped at a sovereign defined ceiling (often level 2 or 3). |
EOF
expect_fail "a trust list state whose trust level is capped fails" "$T" "sovereign-federation.md:4"

T="$(new_tree verb-object)"
printf 'A common pattern: honor the credential but cap the trust level when it comes from abroad.\n' > "$T/sovereign-federation.md"
expect_fail "a verifier told to cap the trust level fails" "$T" "sovereign-federation.md:1"

T="$(new_tree heading)"
printf '## 4. Cross border cosigning\n\n### 4.4 Trust level downgrade across borders\n' > "$T/sovereign-federation.md"
expect_fail "a heading that names a trust level downgrade fails" "$T" "sovereign-federation.md:3"

T="$(new_tree wrapped)"
printf 'Intro.\n\nThe verifier reads the signed `trustLevel`\nof the credential and\nlowers it to the local ceiling.\n' > "$T/core.md"
expect_fail "a sentence split by soft line breaks fails at the line of its verb" "$T" "core.md:5"

T="$(new_tree far-denial)"
printf 'The credential is not rejected: instead its trust level is capped.\n\nThe trust level is capped, not rejected.\n' > "$T/core.md"
expect_fail "a denial more than three words before the verb does not excuse it" "$T" "core.md:1"
expect_fail "a denial after the verb does not excuse it" "$T" "core.md:3"

T="$(new_tree denied)"
cat > "$T/core.md" <<'EOF'
A verifier MUST NOT lower the `trustLevel` and MUST NOT omit the field. No verifier lowers a
signed trust level, a trust level is never capped, and a relying party cannot downgrade the
trust level without lowering it in bytes no issuer signed.
EOF
expect_pass "a sentence that denies the lowering passes" "$T"

T="$(new_tree marker)"
cat > "$T/sovereign-federation.md" <<'EOF'
The verifier reports the ceiling as its own marker beside the signed trust level, and policy
acts on the lower of the two. A node without the root cosignature issues at trust level 3 or
lower. The UK accepts the ATX under a lower ceiling for write operations than its trust level.
EOF
expect_pass "a ceiling beside the signed level, and lower as a comparison, pass" "$T"

T="$(new_tree elsewhere)"
cat > "$T/core.md" <<'EOF'
The trust level is signed. Fees are capped.

The trust level

is unrelated to a rate that was lowered.

| Trust level | Capped fee |
|---|---|
| 3 | A request falls back to the cache |

* The trust level is 3.
* The rate limit is capped.
EOF
expect_pass "the verb in another sentence, paragraph, table cell or list item passes" "$T"

# --- capability-authorized --------------------------------------------------

T="$(new_tree authorizes)"
printf 'The credential is honored. The capabilities the credential authorizes are constrained at the verifier.\n' > "$T/sovereign-federation.md"
expect_fail "capabilities that a credential authorizes fail" \
    "$T" "sovereign-federation.md:1" capability-authorized

T="$(new_tree oversight-row)"
cat > "$T/sovereign-federation.md" <<'EOF'
| EU AI Act requirement | ATX evidence |
|---|---|
| Human oversight | AIM capability grants in the ATX show human authorized capabilities |
EOF
expect_fail "a table row that calls capabilities human authorized fails" \
    "$T" "sovereign-federation.md:3" capability-authorized

T="$(new_tree authorised-wrapped)"
printf 'Intro.\n\nEach capability in the credential is\nauthorised by the operator.\n' > "$T/scalability.md"
expect_fail "the verb in its other spelling, after a soft line break, fails at its own line" \
    "$T" "scalability.md:4" capability-authorized

T="$(new_tree reach)"
cat > "$T/sovereign-federation.md" <<'EOF'
The credential's `capabilities` are what its build is attested to be able to do, not permission:
whether the agent may perform a write is a broker policy decision under AAP. Capabilities do not
authorize anything. A consumer that makes an authorization or trust decision on `capabilities`
requires `atcVersion` 1.1.
EOF
expect_pass "capabilities as attested reach, a denial, and the noun authorization pass" "$T"

T="$(new_tree authorized-elsewhere)"
printf 'The node runs in a FedRAMP authorized environment. Its capabilities are listed.\n\nThe `capabilityJustification` map is authorized by its publisher.\n' > "$T/sovereign-federation.md"
expect_pass "authorized in another sentence, or beside capabilityJustification, passes" "$T"

# --- both rules, every sentence ---------------------------------------------

T="$(new_tree both)"
cat > "$T/sovereign-federation.md" <<'EOF'
The ATX is accepted at a capped trust level, and the capabilities it authorizes are constrained.

The trust level is lowered for write operations.
EOF
expect_fail "one sentence that breaks both rules reports the trust level" "$T" "sovereign-federation.md:1"
expect_fail "one sentence that breaks both rules reports the capabilities" \
    "$T" "sovereign-federation.md:1" capability-authorized
expect_fail "a second failing sentence in the same file is reported too" "$T" "sovereign-federation.md:3"

# --- which files are checked ------------------------------------------------

T="$(new_tree history)"
mkdir -p "$T/errata"
printf 'Clean.\n' > "$T/core.md"
printf -- '- Section 9.2 no longer says trust level 4 requests fall back to trust level 3.\n' > "$T/CHANGELOG.md"
printf 'oldText: |\n  The capabilities the credential authorizes are constrained at the verifier.\n' > "$T/errata/ATX-E-0001.md"
expect_pass "CHANGELOG.md and errata, which quote earlier text, are not checked" "$T"

T="$(new_tree nested)"
mkdir -p "$T/docs"
printf 'Clean.\n' > "$T/README.md"
printf 'Line one.\nThe trust level is capped.\n' > "$T/docs/notes.md"
expect_fail "a Markdown file in a subdirectory is checked" "$T" "docs/notes.md:2"

T="$(new_tree hidden-dir)"
mkdir -p "$T/.suite"
printf 'Clean.\n' > "$T/README.md"
printf 'The trust level is capped.\n' > "$T/.suite/README.md"
expect_pass "hidden directories such as a suite checkout are not checked" "$T"

T="$(new_tree not-utf8)"
printf 'Clean.\n' > "$T/README.md"
printf 'The trust level is capped. \377\n' > "$T/latin.md"
expect_fail "a Markdown file that is not UTF-8 fails rather than being skipped" \
    "$T" "latin.md" not-utf-8

T="$(new_tree empty)"
run_check "$T"
if [ $? -eq 1 ] && grep -q "refusing to pass vacuously" "$OUT"; then
    ok "a tree with no Markdown files exits 1 instead of passing vacuously"
else
    not_ok "a tree with no Markdown files exits 1 instead of passing vacuously" \
        "$(head -c 400 "$OUT" | tr '\n' ' ')"
fi

# --- large input ------------------------------------------------------------

# One paragraph of many failing sentences, then one sentence of many denied verbs: each is
# read once, so neither the line count nor the denial lookup grows with what came before.
T="$(new_tree large)"
{
    yes 'The trust level is capped.' | head -n 40000
    printf '\n'
    yes 'the trust level is not capped and' | head -n 40000 | tr '\n' ' '
    printf '\n'
} > "$T/large.md"
run_check_within 20 "$T"
rc=$?
if [ "$rc" -eq 1 ] && grep -qF "large.md:40000 [level-lowered]" "$OUT" \
    && ! grep -qF "large.md:40002 [" "$OUT"; then
    ok "two paragraphs of about 1 MB each, one of many lines and one a single sentence, are checked in time"
else
    not_ok "two paragraphs of about 1 MB each, one of many lines and one a single sentence, are checked in time" \
        "expected exit 1 within 20 s reporting large.md:40000 and not large.md:40002, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
fi

# --- summary ----------------------------------------------------------------

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d of %d test(s) failed\n' "$FAILED" "$COUNT"
    exit 1
fi
printf '# %d test(s) passed\n' "$COUNT"
