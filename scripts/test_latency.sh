#!/usr/bin/env bash
# Tests for scripts/check_latency.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree and asserted to exit 1 naming the file, the line and the rule; the
# delivered tree itself is asserted to exit 0. Shell rather than pytest so it
# runs with nothing installed: bash and python3 are all this needs.
#
#   bash scripts/test_latency.sh
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
    python3 -B "$REPO/scripts/check_latency.py" --root "$1" > "$OUT" 2>&1
}

run_check_within() {  # run_check_within <seconds> <root>: exit 124 when it takes longer
    python3 -B - "$1" "$REPO/scripts/check_latency.py" "$2" > "$OUT" 2>&1 <<'PYEOF'
import subprocess, sys
limit, script, root = float(sys.argv[1]), sys.argv[2], sys.argv[3]
try:
    sys.exit(subprocess.run([sys.executable, "-B", script, "--root", root], timeout=limit).returncode)
except subprocess.TimeoutExpired:
    print(f"still running after {limit:g} s")
    sys.exit(124)
PYEOF
}

new_tree() {  # new_tree <name> -> path to a scratch tree holding a passing README.md
    mkdir -p "$TMP/$1"
    printf '# atx-spec\n\nLocal verification under 5ms.\n' > "$TMP/$1/README.md"
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

# write_core <root> <step 8 text> [<step 5 text>]: line 7 holds the step 8 text
# and line 10 the step 5 text, both items of one numbered list
write_core() {
    local step5="${3-5. If ML-DSA-65 signature is present, verify it too. About 3ms.}"
    cat > "$1/core.md" <<EOF
## 3. The five planes

| Plane | Owner | What it does |
|---|---|---|
| Verification | Any verifier, locally | Signature check. All local. Sub 5ms. |

$2

4. Verify Ed25519 signature against cached issuer public key. Under 1ms.
$step5
EOF
}

GOOD='8. Accept. Warm cache total: under 5ms. A cold cache adds one DID document fetch, for a total under 50ms.'

# --- the delivered tree -----------------------------------------------------

expect_pass "the repository's own Markdown passes" "$REPO"

# --- latency ----------------------------------------------------------------

T="$(new_tree good)"
write_core "$T" "$GOOD"
expect_pass "totals of 5 ms warm and 50 ms cold pass, and per-step bounds are not totals" "$T"

T="$(new_tree warm-2)"
write_core "$T" '8. Accept. Warm cache total: under 2ms. A cold cache adds one DID document fetch, for a total under 50ms.'
expect_fail "a warm cache total of 2 ms fails" "$T" latency "core.md:7"

T="$(new_tree cold-10)"
write_core "$T" '8. Accept. Warm cache total: under 5ms. Cold cache total: under 10ms with one network fetch for the DID document.'
expect_fail "a cold cache total of 10 ms fails" "$T" latency "core.md:7"

T="$(new_tree prose)"
write_core "$T" 'Total verification time on warm cache is under 2 milliseconds. Cold cache is under 50 milliseconds.'
expect_fail "a total written in milliseconds is checked too" "$T" latency "core.md:7"

T="$(new_tree wrapped)"
write_core "$T" "$GOOD"
printf '\nThe cold\nstart is under 10 ms.\n' >> "$T/core.md"
expect_fail "a kind wrapped across a soft line break is still checked, on the bound's line" \
    "$T" latency "core.md:13"

T="$(new_tree row)"
write_core "$T" "$GOOD"
sed 's/Sub 5ms/Sub 2ms/' "$T/core.md" > "$T/core.tmp" && mv "$T/core.tmp" "$T/core.md"
expect_fail "the Verification plane row takes the warm figure" "$T" latency "core.md:5"

T="$(new_tree range)"
write_core "$T" "$GOOD"
printf '\n| Step | Cost |\n|---|---|\n| Total warm cache | 1 to 8 ms |\n' >> "$T/core.md"
expect_fail "a warm range ending above 5 ms fails" "$T" latency "core.md:14"

T="$(new_tree range-ok)"
write_core "$T" "$GOOD"
printf '\n| Step | Cost |\n|---|---|\n| Total warm cache | 1 to 4 ms |\n' >> "$T/core.md"
expect_pass "a warm range ending at or under 5 ms passes" "$T"

T="$(new_tree other-file)"
write_core "$T" "$GOOD"
printf 'Warm cache verification is under 2 ms.\n' > "$T/notes.md"
expect_fail "every Markdown file is checked, not only core.md" "$T" latency "notes.md:1"

T="$(new_tree history)"
write_core "$T" "$GOOD"
mkdir -p "$T/errata"
printf 'Warm cache total: under 2ms.\n' > "$T/CHANGELOG.md"
printf 'Warm cache total: under 2ms.\n' > "$T/errata/ATX-E-0001.md"
expect_pass "CHANGELOG.md and errata/ quote earlier text and are not checked" "$T"

T="$(new_tree not-utf8)"
write_core "$T" "$GOOD"
printf 'Warm cache total: under 2ms. \377\n' > "$T/latin.md"
expect_fail "a Markdown file that is not UTF-8 fails rather than being skipped" "$T" latency "latin.md"

T="$(new_tree large)"
write_core "$T" "$GOOD"
python3 -B - "$T/large.md" <<'PYEOF'
import sys
lines = "Warm cache verification is under 5 ms.\n" * 60000
sentence = "warm cache under 5 ms, " * 60000
with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write("# Large\n\n" + lines + "\n" + sentence + "\n")
PYEOF
run_check_within 20 "$T"
rc=$?
if [ "$rc" -eq 0 ]; then
    ok "two paragraphs of about 1.4 MB each, one of many lines and one a single sentence, are checked in time"
else
    not_ok "two paragraphs of about 1.4 MB each, one of many lines and one a single sentence, are checked in time" \
        "expected exit 0 within 20 s, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
fi

# --- step -------------------------------------------------------------------

T="$(new_tree step-whole)"
write_core "$T" "$GOOD" '5. If ML-DSA-65 signature is present, verify it too. Under 5ms.'
expect_fail "one step bounded by the whole warm total of its list fails" "$T" step "core.md:10"

T="$(new_tree step-range)"
write_core "$T" "$GOOD" '5. If ML-DSA-65 signature is present, verify it too. 2 to 6 ms.'
expect_fail "one step whose range ends above the warm total of its list fails" "$T" step "core.md:10"

T="$(new_tree step-under)"
write_core "$T" "$GOOD" '5. If ML-DSA-65 signature is present, verify it too. Under 4ms.'
expect_pass "one step bounded below the warm total of its list passes" "$T"

T="$(new_tree step-other-list)"
write_core "$T" "$GOOD" '
The steps below are not part of verification.

1. Fetch the DID document over the network. Under 40ms.'
printf '\nThe cosignature is one Ed25519 signature plus one DID document lookup. Sub 5 ms.\n' >> "$T/core.md"
expect_pass "a per-step bound in a list or paragraph that states no warm total is not checked" "$T"

# --- missing ----------------------------------------------------------------

T="$(new_tree no-cold)"
write_core "$T" '8. Accept.'
expect_fail "core.md stating no cold cache total fails instead of passing vacuously" \
    "$T" missing "core.md"

T="$(new_tree no-readme)"
write_core "$T" "$GOOD"
printf '# atx-spec\n' > "$T/README.md"
expect_fail "README.md stating no warm cache total fails instead of passing vacuously" \
    "$T" missing "README.md"

T="$(new_tree empty)"
rm "$T/README.md"
expect_fail "a tree with no Markdown fails instead of passing vacuously" \
    "$T" missing "core.md"

# --- summary ----------------------------------------------------------------

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d of %d test(s) failed\n' "$FAILED" "$COUNT"
    exit 1
fi
printf '# %d test(s) passed\n' "$COUNT"
