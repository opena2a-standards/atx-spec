#!/usr/bin/env bash
# Tests for scripts/check_revocation_fixture_key.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree and a scratch suite and asserted to exit 1 naming the place and the rule;
# the delivered core.md is asserted to exit 0 against a scratch suite whose two
# revocation fixtures name the agent by agentId in their revocation list, as
# the atx-conformance fixtures do. Shell rather than pytest so it runs with
# nothing installed: bash and python3 are all this needs.
#
#   bash scripts/test_revocation_fixture_key.sh
#
# Set ATX_CONFORMANCE_SUITE to a checkout of opena2a-standards/atx-conformance
# to also run the delivered core.md against the real suite; it is skipped
# otherwise. Output is TAP-ish: one line per leaf test. Exit 0 when every test
# passes.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
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

run_check() {  # run_check <root> <suite>
    python3 -B "$REPO/scripts/check_revocation_fixture_key.py" --root "$1" --suite "$2" > "$OUT" 2>&1
}

new_dir() {  # new_dir <name> -> path to an empty scratch directory
    mkdir -p "$TMP/$1"
    printf '%s' "$TMP/$1"
}

expect_fail() {  # expect_fail <leaf name> <root> <suite> <where> <rule> [<detail> ...]
    # A detail that starts with ! must not be reported.
    local name="$1" root="$2" suite="$3" where="$4" rule="$5" detail rc
    shift 5
    run_check "$root" "$suite"
    rc=$?
    if [ "$rc" -ne 1 ]; then
        not_ok "$name" "expected exit 1, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
        return
    fi
    if ! grep -qF -- "$where [$rule]" "$OUT"; then
        not_ok "$name" "exit 1 but '$where [$rule]' not reported: $(head -c 400 "$OUT" | tr '\n' ' ')"
        return
    fi
    for detail in "$@"; do
        case "$detail" in
            '!'*)
                if grep -qF -- "${detail#!}" "$OUT"; then
                    not_ok "$name" "'${detail#!}' reported: $(head -c 400 "$OUT" | tr '\n' ' ')"
                    return
                fi
                ;;
            *)
                if ! grep -qF -- "$detail" "$OUT"; then
                    not_ok "$name" "exit 1 but '$detail' not reported: $(head -c 400 "$OUT" | tr '\n' ' ')"
                    return
                fi
                ;;
        esac
    done
    ok "$name"
}

one_line_naming() {  # one_line_naming <leaf name> <text>: the last run printed one line with it
    if [ "$(grep -cF -- "$2" "$OUT")" -eq 1 ]; then
        ok "$1"
    else
        not_ok "$1" "expected one line naming '$2': $(head -c 400 "$OUT" | tr '\n' ' ')"
    fi
}

expect_pass() {  # expect_pass <leaf name> <root> <suite>
    local name="$1" rc
    run_check "$2" "$3"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        ok "$name"
    else
        not_ok "$name" "expected exit 0, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
    fi
}

# write_core <root> <Coverage paragraph text> [<step 6 line>]
# Step 6 is on line 5 and the Coverage paragraph on line 11.
write_core() {
    local step6="${3-6. Check \`agentDid\` against locally cached CRL. If listed, reject.}"
    printf '%s\n' \
        "### 1.3 Local verification algorithm" "" \
        "5. Verify every remaining declared signature." "" \
        "$step6" "" \
        "### 1.3a Canonical signing form" "" \
        "## 12. Conformance" "" \
        "**Coverage.** $2" "" \
        "## 13. Security considerations" > "$1/core.md"
}

# write_fixture <suite> <name> [<key> ...]
# A fixture whose verifier state carries a revocation list with one entry that
# names the agent by each key given. With no key the fixture carries no list.
write_fixture() {
    local suite="$1" name="$2" key members=""
    shift 2
    mkdir -p "$suite/fixtures"
    if [ "$#" -eq 0 ]; then
        printf '{"name": "%s", "verifierState": {"clockRfc3339": "2026-05-24T00:00:00Z"}, "atx": {"agentId": "agent_test_001"}}\n' \
            "$name" > "$suite/fixtures/$name.json"
        return
    fi
    for key in "$@"; do
        members="$members\"$key\": \"agent_test_001\", "
    done
    printf '{"name": "%s", "verifierState": {"clockRfc3339": "2026-05-24T00:00:00Z", "crl": {"version": 1, "entries": [{%s"revokedAt": "2026-05-23T12:00:00Z", "reason": "test"}]}}, "atx": {"agentId": "agent_test_001"}}\n' \
        "$name" "$members" > "$suite/fixtures/$name.json"
}

# fixture_deep <suite> <name> <depth> <array|object>
# A fixture that is an array nested <depth> deep ([[...0...]]), or <depth>
# objects each nested in the one before through a ({"a": {"a": ... 1}}).
fixture_deep() {
    mkdir -p "$1/fixtures"
    python3 -B -c '
import sys
depth, kind = int(sys.argv[1]), sys.argv[2]
if kind == "array":
    sys.stdout.write("[" * depth + "0" + "]" * depth)
else:
    sys.stdout.write("{\"a\": " * depth + "1" + "}" * depth)
' "$3" "$4" > "$1/fixtures/$2.json"
}

# The depth at which json.loads stops with a RecursionError depends on the
# Python version and the stack size, so the deep fixtures are built from the
# deepest array json.loads reads here, found by bisection up to 2,000,000, as
# scripts/test_tbs_numbers.sh finds it.
LOADS_DEPTH="$(python3 -B -c '
import json
low, high = 0, 2000000
while low < high:
    mid = (low + high + 1) // 2
    try:
        json.loads("[" * mid + "0" + "]" * mid)
        low = mid
    except RecursionError:
        high = mid - 1
print(low)
')"

# The fixtures of the atx-conformance suite that matter here: two revocation
# fixtures whose list entries name the agent by agentId, and one without a list.
S="$(new_dir upstream-suite)"
write_fixture "$S" baseline-valid
write_fixture "$S" revoked agentId
write_fixture "$S" revoked-crl-only agentId

# The same fixtures keyed by agentDid, the key core.md section 1.3 step 6 looks up.
SD="$(new_dir did-suite)"
write_fixture "$SD" baseline-valid
write_fixture "$SD" revoked agentDid
write_fixture "$SD" revoked-crl-only agentDid

GOOD_PARA="Both revocation fixtures name the agent by \`agentId\`, where step 6 looks up \`agentDid\`."
QUIET_PARA="The revocation-list check of §1.3 step 6 has a fixture of its own, \`revoked-crl-only\`."
REPO_COVERAGE="core.md:$(grep -n '^\*\*Coverage\.\*\*' "$REPO/core.md" | head -n 1 | cut -d: -f1)"

# --- the delivered tree -----------------------------------------------------

expect_pass "the repository's own core.md names the key the suite's revocation lists use" "$REPO" "$S"

if [ -n "${ATX_CONFORMANCE_SUITE-}" ]; then
    expect_pass "the repository's own core.md agrees with the real suite" "$REPO" "$ATX_CONFORMANCE_SUITE"
else
    skip "the repository's own core.md agrees with the real suite" "ATX_CONFORMANCE_SUITE not set"
fi

expect_fail "the repository's own core.md fails against a suite keyed by agentDid, so its note cannot outlive the keying" \
    "$REPO" "$SD" "$REPO_COVERAGE" stale "\`agentId\`"

# --- unnamed ----------------------------------------------------------------

T="$(new_dir named)"
write_core "$T" "$GOOD_PARA"
expect_pass "a Coverage sentence naming the fixtures' key beside the step 6 key passes" "$T" "$S"

T="$(new_dir quiet)"
write_core "$T" "$QUIET_PARA"
expect_fail "a Coverage paragraph that does not name the fixtures' key fails" \
    "$T" "$S" "core.md:11" unnamed "fixtures/revoked-crl-only.json, fixtures/revoked.json names the revoked agent by \`agentId\`"

T="$(new_dir apart)"
write_core "$T" "The lists name the agent by \`agentId\`. Step 6 looks up \`agentDid\`."
expect_fail "the fixtures' key and the step 6 key named in different sentences fail" \
    "$T" "$S" "core.md:11" unnamed

T="$(new_dir unticked)"
write_core "$T" "Both revocation fixtures name the agent by agentId, where step 6 looks up \`agentDid\`."
expect_fail "the fixtures' key named outside backticks fails" \
    "$T" "$S" "core.md:11" unnamed

T="$(new_dir before-coverage)"
write_core "$T" "$QUIET_PARA"
sed 's/^## 12\. Conformance$/## 12. Conformance\
\
Both revocation fixtures name the agent by `agentId`, where step 6 looks up `agentDid`./' \
    "$T/core.md" > "$T/core.tmp" && mv "$T/core.tmp" "$T/core.md"
expect_fail "the fixtures' key named in another paragraph of section 12 does not count" \
    "$T" "$S" "core.md:13" unnamed

T="$(new_dir old-step-6)"
write_core "$T" "$QUIET_PARA" "6. Check \`agentId\` against locally cached CRL. If listed, reject."
expect_pass "a step 6 that looks up the fixtures' key needs no note" "$T" "$S"

# --- stale ------------------------------------------------------------------

T="$(new_dir stale)"
write_core "$T" "$GOOD_PARA"
expect_fail "a key no fixture's revocation list uses, named beside the step 6 key, fails" \
    "$T" "$SD" "core.md:11" stale "names \`agentId\` beside \`agentDid\`"

T="$(new_dir did-quiet)"
write_core "$T" "$QUIET_PARA"
expect_pass "a suite whose lists use the step 6 key needs no note" "$T" "$SD"

T="$(new_dir other-sentence)"
write_core "$T" "Credentials carry \`agentId\` and \`agentVersion\`. $QUIET_PARA"
expect_pass "agent keys in a sentence that does not name the step 6 key are not read" "$T" "$SD"

# --- missing ----------------------------------------------------------------

T="$(new_dir no-core)"
expect_fail "a tree with no core.md fails instead of passing vacuously" \
    "$T" "$S" "core.md" missing "file not found"

T="$(new_dir no-step-key)"
write_core "$T" "$GOOD_PARA" "6. Check the agent against locally cached CRL. If listed, reject."
expect_fail "a step 6 that names no agent key in backticks fails" \
    "$T" "$S" "core.md:5" missing "names no agent key"

T="$(new_dir no-step-6)"
write_core "$T" "$GOOD_PARA" "7. Count distinct signer authorities."
expect_fail "a section 1.3 with no step 6 fails" \
    "$T" "$S" "core.md" missing "no line opening step 6"

T="$(new_dir no-anchor)"
write_core "$T" "$GOOD_PARA"
sed 's/^\*\*Coverage\.\*\*/**Gaps.**/' "$T/core.md" > "$T/core.tmp" && mv "$T/core.tmp" "$T/core.md"
expect_fail "a renamed Coverage paragraph fails instead of passing vacuously" \
    "$T" "$S" "core.md" missing "no line opening with **Coverage.**"

T="$(new_dir named-for-suites)"
write_core "$T" "$GOOD_PARA"

S2="$(new_dir empty-suite)"
expect_fail "a suite with no fixtures fails instead of passing vacuously" \
    "$T" "$S2" "fixtures" missing "no fixtures/*.json"

S3="$(new_dir no-list-suite)"
write_fixture "$S3" baseline-valid
expect_fail "a suite in which no fixture gives the verifier a revocation list fails" \
    "$T" "$S3" "fixtures" missing "gives the verifier a revocation list"

# --- fixture ----------------------------------------------------------------

S4="$(new_dir truncated-suite)"
write_fixture "$S4" revoked agentId
printf '{"name": ' > "$S4/fixtures/truncated.json"
expect_fail "a fixture that is not JSON fails" \
    "$T" "$S4" "fixtures/truncated.json" fixture "cannot be read as JSON"

S5="$(new_dir entries-object-suite)"
write_fixture "$S5" revoked agentId
printf '{"name": "odd", "verifierState": {"crl": {"version": 1, "entries": {"agentId": "agent_test_001"}}}}\n' \
    > "$S5/fixtures/odd.json"
expect_fail "a revocation list whose entries are not an array of objects fails" \
    "$T" "$S5" "fixtures/odd.json" fixture "entries array of objects"

# A fixture nested twice as deep as json.loads reads fails on one line, not with
# a RecursionError traceback, and the fixture after it is still read: under a
# Coverage paragraph that names no agent key, the key its list uses is reported
# as unnamed.
DEEP_READ='[fixture] cannot be read as JSON: it nests arrays or objects deeper than the json module of this Python can read'
if [ "$LOADS_DEPTH" -lt 2000000 ]; then
    Q="$(new_dir quiet-beside-deep)"
    write_core "$Q" "$QUIET_PARA"
    S6="$(new_dir deep-array-suite)"
    fixture_deep "$S6" deep "$((2 * LOADS_DEPTH))" array
    write_fixture "$S6" revoked agentId
    expect_fail "a fixture nested in arrays deeper than json.loads reads fails as not JSON" \
        "$Q" "$S6" "fixtures/deep.json" fixture "fixtures/deep.json $DEEP_READ" \
        "core.md:11 [unnamed] the revocation list of fixtures/revoked.json names the revoked agent by \`agentId\`" \
        '!Traceback'
    one_line_naming "a fixture nested in arrays deeper than json.loads reads is reported on one line" \
        "fixtures/deep.json"

    # A suite whose one fixture is nested that deep gives the verifier no
    # revocation list, so the missing line is reported beside it.
    S7="$(new_dir deep-object-suite)"
    fixture_deep "$S7" deep "$((2 * LOADS_DEPTH))" object
    expect_fail "a suite whose one fixture nests objects deeper than json.loads reads fails as not JSON" \
        "$T" "$S7" "fixtures/deep.json" fixture "fixtures/deep.json $DEEP_READ" \
        "fixtures [missing] no fixture under" '!Traceback'
    one_line_naming "a fixture nested in objects deeper than json.loads reads is reported on one line" \
        "fixtures/deep.json"
else
    for leaf in "a fixture nested in arrays deeper than json.loads reads fails as not JSON" \
        "a fixture nested in arrays deeper than json.loads reads is reported on one line" \
        "a suite whose one fixture nests objects deeper than json.loads reads fails as not JSON" \
        "a fixture nested in objects deeper than json.loads reads is reported on one line"; do
        skip "$leaf" "json.loads reads 2,000,000 levels here"
    done
fi

# --- summary ----------------------------------------------------------------

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d of %d test(s) failed\n' "$FAILED" "$COUNT"
    exit 1
fi
printf '# %d test(s) passed, %d skipped\n' "$((COUNT - SKIPPED))" "$SKIPPED"
