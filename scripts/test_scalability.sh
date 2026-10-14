#!/usr/bin/env bash
# Tests for scripts/check_scalability.py.
#
# Each scratch tree is a copy of the delivered scalability.md and core.md with
# one figure or input changed, asserted to exit 1 naming the file, the line and
# the rule; the delivered tree itself is asserted to exit 0. The changed text is
# replaced exactly once, so a test whose phrase has been reworded away fails
# instead of passing. Shell rather than pytest so it runs with nothing
# installed: bash and python3 are all this needs.
#
#   bash scripts/test_scalability.sh
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
    python3 -B "$REPO/scripts/check_scalability.py" --root "$1" > "$OUT" 2>&1
}

new_tree() {  # new_tree <name> -> path to a scratch copy of the delivered documents
    mkdir -p "$TMP/$1"
    cp "$REPO/scalability.md" "$REPO/core.md" "$TMP/$1/"
    printf '%s' "$TMP/$1"
}

# change <leaf name> <tree> <old> <new>: replace <old> with <new> in the tree's
# scalability.md, failing the leaf test unless <old> occurs exactly once
change() {
    local name="$1" doc="$2/scalability.md" err
    if ! err="$(python3 -B - "$doc" "$3" "$4" 2>&1 <<'PYEOF'
import sys
path, old, new = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
if text.count(old) != 1:
    sys.exit(f"expected {old!r} once in scalability.md, found it {text.count(old)} times")
open(path, "w", encoding="utf-8").write(text.replace(old, new))
PYEOF
)"; then
        not_ok "$name" "$err"
        return 1
    fi
}

line_of() {  # line_of <tree> <text>: the line of scalability.md holding <text>
    grep -n -F -m 1 -- "$2" "$1/scalability.md" | cut -d: -f1
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
        not_ok "$name" "exit 1 but '$where [$rule]' not reported: $(head -c 600 "$OUT" | tr '\n' ' ')"
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
        not_ok "$name" "expected exit 0, got $rc: $(head -c 600 "$OUT" | tr '\n' ' ')"
    fi
}

# fails <leaf name> <tree name> <rule> <old> <new> [<text on the reported line>]
fails() {
    local name="$1" rule="$3" old="$4" new="$5" T
    T="$(new_tree "$2")"
    change "$name" "$T" "$old" "$new" || return
    expect_fail "$name" "$T" "$rule" "scalability.md:$(line_of "$T" "${6:-$new}")"
}

# passes <leaf name> <tree name> <old> <new>
passes() {
    local name="$1" T
    T="$(new_tree "$2")"
    change "$name" "$T" "$3" "$4" || return
    expect_pass "$name" "$T"
}

# --- the delivered tree -----------------------------------------------------

expect_pass "the repository's scalability.md passes" "$REPO"

# --- verification -----------------------------------------------------------

fails "a warm total of 1 to 4 ms fails: the steps sum to 3.611 ms" total-range total \
    '| 3.5 to 3.6 ms |' '| 1 to 4 ms |'

passes "a warm total stated as one rounded figure passes" total-about \
    '| 3.5 to 3.6 ms |' '| About 3.6 ms |'

fails "a step cost that changes without the total fails" step-cost total \
    '| ML-DSA-65 signature verify | 3 ms |' '| ML-DSA-65 signature verify | 1 ms |' \
    '| Total warm cache |'

fails "1,000 verifications per second per core fails: 1,000 ms over 3.611 ms is 277" per-core per-core \
    'about 277 verifications per second per core' 'approximately 1,000 verifications per second per core'

passes "a per-core figure rounded to two significant digits passes" per-core-round \
    'about 277 verifications per second per core' 'about 280 verifications per second per core'

fails "4,000 verifications per second for four cores fails" per-host per-host \
    'Four cores yield about 1,100 verifications' 'Four cores yields 4,000 verifications'

fails "250,000 verifiers for a billion verifications per second fails" verifiers verifiers \
    'there are about 900,000 such verifiers' 'there are 250,000 such verifiers'

# --- log --------------------------------------------------------------------

fails "an issuance rate that is not a billion weekly fails" rate rate \
    'approximately 1,650 issuances per second' 'approximately 165 issuances per second'

fails "4 TB for a month of log entries fails: it is 1.1 TB" month log-size \
    'roughly 1.1 TB:' 'roughly 4 TB:'

passes "a month of log entries written in GB passes" month-gb \
    'roughly 1.1 TB:' 'roughly 1,100 GB:'

fails "a trillion entries not at the stated entry size fails" trillion log-size \
    'per entry is 256 TB' 'per entry is 25 TB'

# --- storage ----------------------------------------------------------------

fails "a credential of 1 to 4 KB fails: its signatures alone are 4,500 bytes" parse-size credential \
    'Bounded by JSON length, about 6 KB:' 'Bounded by JSON length, typically 1 to 4 KB:'

fails "a credential averaging 2 KB fails" average-size credential \
    'each about 6 KB (section 2.1)' 'each averaging 2 KB (section 2.1)'

fails "2 TB for a billion credentials fails" active-set storage \
    'That is 6 TB of hot storage' 'That is 2 TB of hot storage'

fails "200 MB for 100,000 credentials fails" node-active storage \
    'at about 6 KB each = 600 MB' 'at about 6 KB each = 200 MB'

fails "a reissuance data rate no stated issuance rate gives fails" reissuance reissuance \
    'about 60 KB per second.' 'about 150 KB per second.'

fails "10 GB a year of log mirror for 100,000 agents fails: it is 1.3 GB" log-mirror log-mirror \
    'mirror: about 1.3 GB per year' 'mirror: ~10 GB per year'

# --- capacity ---------------------------------------------------------------

fails "a section 10 sentence that makes the table a conformance criterion fails" capacity capacity \
    'Suggested sizing per node tier.' \
    'Hard numbers per node tier. These are the minimum capacities a node must support to claim ATP conformance.'

# --- missing and encoding ---------------------------------------------------

T="$(new_tree no-per-core)"
if change "a per-core figure reworded away fails instead of passing vacuously" "$T" \
    'verifications per second per core' 'checks a second on each core'; then
    expect_fail "a per-core figure reworded away fails instead of passing vacuously" \
        "$T" missing "scalability.md"
fi

T="$(new_tree no-core)"
rm "$T/core.md"
expect_fail "a tree without core.md fails: the credential cannot be sized" "$T" missing "scalability.md"

T="$(new_tree not-utf8)"
printf 'Hot storage. \377\n' >> "$T/scalability.md"
expect_fail "a scalability.md that is not UTF-8 fails rather than being skipped" "$T" encoding "scalability.md"

mkdir -p "$TMP/empty"
expect_fail "a tree with no scalability.md fails instead of passing vacuously" "$TMP/empty" missing "scalability.md"

# --- summary ----------------------------------------------------------------

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d of %d test(s) failed\n' "$FAILED" "$COUNT"
    exit 1
fi
printf '# %d test(s) passed\n' "$COUNT"
