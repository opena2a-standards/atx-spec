#!/usr/bin/env bash
# Tests for scripts/check_revocation_cursor.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree and asserted to exit 1 naming the file, the line and the rule; the
# delivered tree itself is asserted to exit 0. Shell rather than pytest so it
# runs with nothing installed: bash and python3 are all this needs.
#
#   bash scripts/test_revocation_cursor.sh
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
    python3 -B "$REPO/scripts/check_revocation_cursor.py" --root "$1" > "$OUT" 2>&1
}

run_check_within() {  # run_check_within <seconds> <root>: exit 124 when it takes longer
    python3 -B - "$1" "$REPO/scripts/check_revocation_cursor.py" "$2" > "$OUT" 2>&1 <<'PYEOF'
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

expect_fail() {  # expect_fail <leaf name> <root> <file:line> [rule, default crl-version]
    local name="$1" root="$2" where="$3" rule="${4:-crl-version}" rc
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

# --- crl-version ------------------------------------------------------------

T="$(new_tree revocation-step)"
cat > "$T/core.md" <<'EOF'
### 3.3 Revocation flow

1. Revocation trigger fires.
2. Issuing node marks ATX as revoked. Adds REVOCATION entry to transparency log. Increments CRL version.
EOF
expect_fail "a revocation step that increments a CRL version fails" "$T" "core.md:4"

T="$(new_tree wrapped)"
printf 'Intro.\n\nVerifiers compare the cached CRL\nversion with the published one.\n' > "$T/scalability.md"
expect_fail "the phrase split by a soft line break fails" "$T" "scalability.md:3"

T="$(new_tree long-form)"
printf 'The node bumps its Revocation-List Version on every entry.\n' > "$T/sovereign-federation.md"
expect_fail "revocation list version fails in any case and with a hyphen" \
    "$T" "sovereign-federation.md:1"

T="$(new_tree cursor)"
printf 'Advances the `nextSince` cursor that the ATP-SPEC v1.0.0-rc1 section 8.1 revocation response returns.\n' > "$T/core.md"
expect_pass "naming the nextSince cursor passes" "$T"

T="$(new_tree other-versions)"
printf 'Check atxVersion is supported. The CRL is versioned by STH. Document version: 1.1.0.\n' > "$T/core.md"
expect_pass "other version words near CRL are not the phrase" "$T"

T="$(new_tree history)"
mkdir -p "$T/errata"
printf 'Clean.\n' > "$T/core.md"
printf -- '- Step 2 no longer says Increments CRL version.\n' > "$T/CHANGELOG.md"
printf 'oldText: |\n  Increments CRL version.\n' > "$T/errata/ATX-E-0001.md"
expect_pass "CHANGELOG.md and errata, which quote earlier text, are not checked" "$T"

T="$(new_tree nested)"
mkdir -p "$T/docs"
printf 'Clean.\n' > "$T/README.md"
printf 'Line one.\nThe CRL version advances.\n' > "$T/docs/notes.md"
expect_fail "a Markdown file in a subdirectory is checked" "$T" "docs/notes.md:2"

T="$(new_tree hidden-dir)"
mkdir -p "$T/.suite"
printf 'Clean.\n' > "$T/README.md"
printf 'The CRL version advances.\n' > "$T/.suite/README.md"
expect_pass "hidden directories such as a suite checkout are not checked" "$T"

# --- crl-key ----------------------------------------------------------------

T="$(new_tree key-step)"
cat > "$T/core.md" <<'EOF'
### 1.3 Local verification algorithm

5. Verify every remaining declared signature.
6. Check agentId against locally cached CRL. If listed, reject.
EOF
expect_fail "a verification step that looks agentId up in the CRL fails" "$T" "core.md:4" crl-key

T="$(new_tree key-wrapped)"
printf 'Intro.\n\nThe verifier matches the `agentId` of the credential\nagainst the cached Revocation-List entries.\n' > "$T/scalability.md"
expect_fail "agentId and the revocation list split by a soft line break fail, in any case" \
    "$T" "scalability.md:3" crl-key

T="$(new_tree key-did)"
printf '6. Check `agentDid` against the locally cached CRL (ATP-SPEC v1.0.0-rc1 §8.1). If listed, reject.\n' > "$T/core.md"
expect_pass "looking agentDid up in the CRL passes" "$T"

T="$(new_tree key-other-sentence)"
printf 'An SSE event names this agentId. Verifiers detect it on their next CRL refresh.\n\nThe agentId field\n\nis unrelated to the revocation list.\n' > "$T/core.md"
expect_pass "agentId in one sentence and the list in the next, or past a blank line, passes" "$T"

T="$(new_tree key-list-first)"
printf 'A full CRL listing every revoked agentId is small.\n' > "$T/scalability.md"
expect_pass "the list named before agentId is not a lookup of agentId" "$T"

T="$(new_tree key-history)"
mkdir -p "$T/errata"
printf 'Clean.\n' > "$T/core.md"
printf -- '- Step 6 no longer says Check agentId against locally cached CRL.\n' > "$T/CHANGELOG.md"
printf 'oldText: |\n  6. Check agentId against locally cached CRL.\n' > "$T/errata/ATX-E-0001.md"
expect_pass "CHANGELOG.md and errata quoting the old lookup are not checked" "$T"

# --- one scan ---------------------------------------------------------------

# The crl-key rule finds each agentId, each list and each sentence end once per
# file and pairs them in one pass. It must report what the single regex it
# replaced reported, kept here as the reference: agentId, then the list later
# in the same sentence, with no sentence end and no blank line between them,
# the next match looked for after the end of that list.
python3 -B - "$REPO/scripts" > "$OUT" 2>&1 <<'PYEOF'
import random, re, sys
sys.path.insert(0, sys.argv[1])
import check_revocation_cursor as check

REFERENCE = re.compile(
    r"\bagentId\b(?:(?![.!?](?:\s|$))(?!\n[ \t]*\n)[\s\S])*?"
    r"\b(?i:CRL|revocation[\s-]+list)\b"
)
PIECES = [
    "agentId", "agentId", "agentId", "AgentId", "agentIds", "xagentId", "agentId_",
    "CRL", "crl", "CRLs", "xCRL", "revocation", "Revocation", "list", "LIST",
    "revocation list", "revocation-list", "Revocation - List", "revocation\nlist",
    "revocation\n\nlist", " ", " ", " ", "\t", "\xa0", "\n", "\n\n", "\n \t\n", "\n  ",
    ".", "!", "?", ". ", ".\n", "e.g", "v1.0", "-", "x", "the ", "\xe9",
]
SEPARATORS = ["", " ", " ", "\n"]
rng = random.Random(1)
matched = several = unmatched = 0
for n in range(5000):
    text = "".join(rng.choice(PIECES) + rng.choice(SEPARATORS) for _ in range(rng.randint(1, 30)))
    want = [m.start() for m in REFERENCE.finditer(text)]
    got = check.key_offsets(text)
    if got != want:
        print(f"text {n} {text!r}: the regex reports {want}, the one scan {got}")
        sys.exit(1)
    if want:
        matched += 1
        several += len(want) > 1
    elif "agentId" in text:
        unmatched += 1
print(f"{matched} texts with a match, {several} of them with more than one, and "
      f"{unmatched} with agentId and no match agree")
sys.exit(0 if several and unmatched else 1)
PYEOF
rc=$?
if [ "$rc" -eq 0 ]; then
    ok "the one scan reports the matches of the single regex on 5000 generated texts: $(tail -n 1 "$OUT")"
else
    not_ok "the one scan reports the matches of the single regex on 5000 generated texts" \
        "$(head -c 400 "$OUT" | tr '\n' ' ')"
fi

# --- time -------------------------------------------------------------------

# The single regex scanned the rest of the sentence again for every agentId in
# it, so a sentence naming agentId many times with no list after it took time
# quadratic in its length: run from the command line, 0.39 s at 16 KB, 1.49 s at
# 32 KB and 5.89 s at 64 KB.
T="$(new_tree large)"
python3 -B - "$T/large.md" <<'PYEOF'
import sys
with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write("# Large\n\n" + "agentId " * 32768 + "\n")
PYEOF
run_check_within 10 "$T"
rc=$?
if [ "$rc" -eq 0 ]; then
    ok "a 256 KB sentence naming agentId 32768 times with no list after it is checked in time"
else
    not_ok "a 256 KB sentence naming agentId 32768 times with no list after it is checked in time" \
        "expected exit 0 within 10 s, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
fi

# Each failure's line was found by counting newlines from the start of the
# file, which took time quadratic in the number of failures.
T="$(new_tree many-failures)"
python3 -B - "$T/many.md" <<'PYEOF'
import sys
with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write("# Many\n\n" + "Check agentId against the CRL.\n" * 80000)
PYEOF
run_check_within 10 "$T"
rc=$?
if [ "$rc" -eq 1 ] && grep -qF "many.md:80002 [crl-key]" "$OUT" \
    && [ "$(grep -cF '[crl-key]' "$OUT")" -eq 80000 ]; then
    ok "a file of 80000 failing lines is checked in time, each failure on its own line"
else
    not_ok "a file of 80000 failing lines is checked in time, each failure on its own line" \
        "expected exit 1 within 10 s reporting many.md:80002 and 80000 failures, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
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
