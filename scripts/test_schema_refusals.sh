#!/usr/bin/env bash
# Tests for scripts/check_schema_refusals.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree and a scratch suite and asserted to exit 1 naming the place and the rule;
# the delivered core.md is asserted to exit 0 against a suite holding one
# fixture of each signature shape the atx-conformance suite has. Each scratch
# fixture is the core.md section 1.1 example with its atcVersion set and its
# signatures cut to the named suites. Needs bash, python3 and the jsonschema
# package, as scripts/validate_examples.py does.
#
#   bash scripts/test_schema_refusals.sh
#
# Set ATX_CONFORMANCE_SUITE to a checkout of opena2a-standards/atx-conformance
# to also run the delivered core.md against the real suite; it is skipped
# otherwise. Output is TAP-ish: one line per leaf test. Exit 0 when every test
# passes.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! python3 -c 'import jsonschema' 2>/dev/null; then
    echo "Bail out! the jsonschema package is required (pip install jsonschema)"
    exit 1
fi

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
    python3 -B "$REPO/scripts/check_schema_refusals.py" --root "$1" --suite "$2" > "$OUT" 2>&1
}

new_dir() {  # new_dir <name> -> path to an empty scratch directory
    mkdir -p "$TMP/$1"
    printf '%s' "$TMP/$1"
}

expect_fail() {  # expect_fail <leaf name> <root> <suite> <where> <rule> [<detail>]
    local name="$1" root="$2" suite="$3" where="$4" rule="$5" detail="${6-}" rc
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
    if [ -n "$detail" ] && ! grep -qF -- "$detail" "$OUT"; then
        not_ok "$name" "exit 1 but '$detail' not reported: $(head -c 400 "$OUT" | tr '\n' ' ')"
        return
    fi
    ok "$name"
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

# write_core <root> <Issuer paragraph text>
# The Issuer paragraph is on line 5. Section 13 names a fixture the schema
# accepts in a refusal sentence, which fails if anything outside section 12 is
# read.
write_core() {
    {
        printf '## 12. Conformance\n\nThree conformance targets exist.\n\n'
        printf '**Issuer.** %s\n\n' "$2"
        printf '## 13. Security considerations\n\n'
        printf 'The credential schema refuses `v1_1-baseline-valid-hybrid` outside section 12.\n'
    } > "$1/core.md"
}

# write_tree <root> <Issuer paragraph text>: core.md and the repository's schema.
write_tree() {
    write_core "$1" "$2"
    mkdir -p "$1/schemas"
    cp "$REPO/schemas/atx-credential-v1.1.schema.json" "$1/schemas/"
}

# write_fixture <suite> <name> <atcVersion> <algorithm>[,<algorithm>...]
# The core.md section 1.1 example with that atcVersion and only the signatures
# of the named suites, as <suite>/fixtures/<name>.json.
write_fixture() {
    mkdir -p "$1/fixtures"
    python3 -B - "$REPO" "$1/fixtures/$2.json" "$3" "$4" <<'PYEOF'
import json
import pathlib
import sys

repo, out, version, wanted = sys.argv[1:5]
sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(repo) / "scripts"))
from validate_examples import extract_block

atx = json.loads(extract_block(pathlib.Path(repo) / "core.md", "### 1.1 ATX schema"))
by_algorithm = {entry["algorithm"]: entry for entry in atx["signatures"]}
atx["atcVersion"] = version
atx["signatures"] = [by_algorithm[alg] for alg in wanted.split(",")]
pathlib.Path(out).write_text(json.dumps({"atx": atx}, indent=2) + "\n", encoding="utf-8")
PYEOF
}

# One fixture of each signature shape the atx-conformance suite has: an
# Ed25519-only 1.0 credential, which the two-suite rule leaves alone, an
# Ed25519-only 1.1 one and an ML-DSA-65-only 1.1 one, which it refuses, and a
# 1.1 one carrying both suites, which it accepts.
S="$(new_dir upstream-suite)"
write_fixture "$S" baseline-valid 1.0 Ed25519
write_fixture "$S" v1_1-baseline-valid 1.1 Ed25519
write_fixture "$S" v1_1-hybrid-pq-only 1.1 ML-DSA-65
write_fixture "$S" v1_1-baseline-valid-hybrid 1.1 Ed25519,ML-DSA-65

GOOD="The Ed25519-only fixtures that declare \`atcVersion\` 1.1 lack the ML-DSA-65 signature §1.1 requires and \`v1_1-hybrid-pq-only\` lacks the Ed25519 one, so the credential schema refuses each of them."

# --- the delivered tree -----------------------------------------------------

expect_pass "the repository's own core.md accounts for every fixture the schema refuses" "$REPO" "$S"

if [ -n "${ATX_CONFORMANCE_SUITE-}" ]; then
    expect_pass "the repository's own core.md agrees with the real suite" "$REPO" "$ATX_CONFORMANCE_SUITE"
else
    skip "the repository's own core.md agrees with the real suite" "ATX_CONFORMANCE_SUITE not set"
fi

T="$(new_dir good)"
write_tree "$T" "Fixtures pin signing bytes. $GOOD"
expect_pass "the Ed25519-only phrase and v1_1-hybrid-pq-only by name pass, and section 13 is not read" "$T" "$S"

T="$(new_dir passive)"
write_tree "$T" "The Ed25519-only fixtures that declare \`atcVersion\` 1.1, and \`v1_1-hybrid-pq-only.json\`, are refused by the credential schema."
expect_pass "\"refused by the credential schema\" and a name written with .json count" "$T" "$S"

S2="$(new_dir accepted-suite)"
write_fixture "$S2" baseline-valid 1.0 Ed25519
write_fixture "$S2" baseline-valid-pq 1.0 ML-DSA-65
write_fixture "$S2" v1_1-baseline-valid-hybrid 1.1 Ed25519,ML-DSA-65
T="$(new_dir accepted)"
write_tree "$T" "Fixtures pin signing bytes and verdicts rather than issuance policy."
expect_pass "one-suite 1.0 fixtures and a two-suite 1.1 fixture, which the schema accepts, need no mention" "$T" "$S2"

# --- unaccounted ------------------------------------------------------------

T="$(new_dir those-of-them)"
write_tree "$T" "All but the hybrid fixtures carry Ed25519 signatures only. Those of them that declare \`atcVersion\` 1.1 lack the ML-DSA-65 signature §1.1 requires, and the credential schema refuses them."
expect_fail "\"those of them that declare atcVersion 1.1\" leaves the Ed25519-only 1.1 fixture unaccounted" \
    "$T" "$S" "core.md:5" unaccounted "fixtures/v1_1-baseline-valid.json"
expect_fail "\"those of them that declare atcVersion 1.1\" leaves v1_1-hybrid-pq-only unaccounted" \
    "$T" "$S" "core.md:5" unaccounted "fixtures/v1_1-hybrid-pq-only.json"

T="$(new_dir no-pq-only)"
write_tree "$T" "The Ed25519-only fixtures that declare \`atcVersion\` 1.1 lack the ML-DSA-65 signature §1.1 requires, and the credential schema refuses them."
expect_fail "a paragraph that leaves out v1_1-hybrid-pq-only fails" \
    "$T" "$S" "core.md:5" unaccounted "fixtures/v1_1-hybrid-pq-only.json"

T="$(new_dir named-elsewhere)"
write_tree "$T" "\`v1_1-hybrid-pq-only\` carries no Ed25519 signature. The credential schema refuses the Ed25519-only fixtures that declare \`atcVersion\` 1.1."
expect_fail "a fixture named only in a sentence that does not say the schema refuses fails" \
    "$T" "$S" "core.md:5" unaccounted "fixtures/v1_1-hybrid-pq-only.json"

T="$(new_dir phrase-elsewhere)"
write_tree "$T" "The Ed25519-only fixtures that declare \`atcVersion\` 1.1 lack the ML-DSA-65 signature. The credential schema refuses \`v1_1-hybrid-pq-only\`."
expect_fail "the Ed25519-only phrase in a sentence that does not say the schema refuses fails" \
    "$T" "$S" "core.md:5" unaccounted "fixtures/v1_1-baseline-valid.json"

T="$(new_dir silent)"
write_tree "$T" "Fixtures pin signing bytes and verdicts rather than issuance policy."
expect_fail "an Issuer paragraph that says nothing about the refused fixtures fails" \
    "$T" "$S" "core.md:5" unaccounted "fixtures/v1_1-baseline-valid.json"

# --- stale ------------------------------------------------------------------

S3="$(new_dir regenerated-suite)"
write_fixture "$S3" baseline-valid 1.0 Ed25519
write_fixture "$S3" v1_1-baseline-valid 1.1 Ed25519,ML-DSA-65
write_fixture "$S3" v1_1-hybrid-pq-only 1.1 ML-DSA-65
T="$(new_dir regenerated)"
write_tree "$T" "$GOOD"
expect_fail "the Ed25519-only phrase fails once no 1.1 fixture carries Ed25519 signatures only" \
    "$T" "$S3" "core.md:5" stale "no fixture in the suite declares atcVersion 1.1"

T="$(new_dir names-accepted)"
write_tree "$T" "$GOOD The credential schema refuses \`v1_1-baseline-valid-hybrid\` as well."
expect_fail "a refusal sentence naming a fixture the schema accepts fails" \
    "$T" "$S" "core.md:5" stale "fixtures/v1_1-baseline-valid-hybrid.json"

# --- missing and fixture ----------------------------------------------------

T="$(new_dir no-anchor)"
write_tree "$T" "$GOOD"
sed 's/^\*\*Issuer\.\*\*/**Issuers.**/' "$T/core.md" > "$T/core.tmp" && mv "$T/core.tmp" "$T/core.md"
expect_fail "a renamed Issuer paragraph fails instead of passing vacuously" \
    "$T" "$S" "core.md" missing "no line opening with **Issuer.**"

T="$(new_dir no-core)"
expect_fail "a tree with no core.md fails instead of passing vacuously" \
    "$T" "$S" "core.md" missing "file not found"

T="$(new_dir no-schema)"
write_core "$T" "$GOOD"
expect_fail "a tree with no schema fails instead of passing vacuously" \
    "$T" "$S" "schemas/atx-credential-v1.1.schema.json" missing

T="$(new_dir tree)"
write_tree "$T" "$GOOD"
S4="$(new_dir empty-suite)"
expect_fail "a suite with no fixtures fails instead of passing vacuously" \
    "$T" "$S4" "fixtures" missing "no fixtures/*.json"

S5="$(new_dir broken-suite)"
write_fixture "$S5" v1_1-baseline-valid 1.1 Ed25519
write_fixture "$S5" v1_1-hybrid-pq-only 1.1 ML-DSA-65
printf '{"name": "no atx member"}\n' > "$S5/fixtures/no-atx.json"
printf '{"atx": ' > "$S5/fixtures/truncated.json"
expect_fail "a fixture with no atx member fails" "$T" "$S5" "fixtures/no-atx.json" fixture
expect_fail "a fixture that is not JSON fails" "$T" "$S5" "fixtures/truncated.json" fixture

# --- summary ----------------------------------------------------------------

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d of %d test(s) failed\n' "$FAILED" "$COUNT"
    exit 1
fi
printf '# %d test(s) passed, %d skipped\n' "$((COUNT - SKIPPED))" "$SKIPPED"
