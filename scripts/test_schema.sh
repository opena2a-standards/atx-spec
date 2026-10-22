#!/usr/bin/env bash
# Tests for schemas/atx-credential-v1.1.schema.json beyond the core.md §1.1 example.
#
# scripts/validate_examples.py validates the §1.1 example as published. Each case
# here takes that example, sets one member of its scanSummary, and asserts that
# the schema accepts the result, or rejects it at the expected JSON path. Needs
# python3 and the jsonschema package that scripts/validate_examples.py needs.
#
#   bash scripts/test_schema.sh
#
# Output is TAP-ish: one line per leaf test. Exit 0 when every test passes.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

# validate <scanSummary member> <JSON value, or "absent">
# Prints "valid", or the JSON path and message of the first error, tab-separated.
validate() {
    python3 -B -c '
import json, pathlib, sys
repo = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(repo / "scripts"))
from jsonschema import Draft202012Validator
from validate_examples import extract_block
schema = json.loads((repo / "schemas" / "atx-credential-v1.1.schema.json").read_text(encoding="utf-8"))
credential = json.loads(extract_block(repo / "core.md", "### 1.1 ATX schema"))
if sys.argv[3] != "absent":
    credential["scanSummary"][sys.argv[2]] = json.loads(sys.argv[3])
errors = sorted(Draft202012Validator(schema).iter_errors(credential), key=lambda e: e.json_path)
print("valid" if not errors else f"{errors[0].json_path}\t{errors[0].message}")
' "$REPO" "$1" "$2" 2>&1
}

expect_valid() {  # expect_valid <leaf name> <member> <value>
    local out
    out="$(validate "$2" "$3")"
    if [ "$out" = "valid" ]; then
        ok "$1"
    else
        not_ok "$1" "expected valid, got: $out"
    fi
}

expect_invalid() {  # expect_invalid <leaf name> <member> <value> <JSON path of the error>
    local out tab=$'\t'
    out="$(validate "$2" "$3")"
    if [ "${out%%"$tab"*}" = "$4" ] && [ "$out" != "$4" ]; then
        ok "$1"
    else
        not_ok "$1" "expected an error at $4, got: $out"
    fi
}

# --- scanSummary.techniques (core.md §1.3a.2 rule 6) -------------------------

expect_valid "the section 1.1 example without techniques is valid" techniques absent
expect_valid "techniques carrying two technique IDs is valid" techniques '["T-4001", "T-5004"]'
expect_valid "an empty techniques array is valid on the wire" techniques '[]'
expect_valid "techniques as null is valid on the wire" techniques 'null'

expect_invalid "techniques as a string is rejected" \
    techniques '"T-4001"' '$.scanSummary.techniques'
expect_invalid "a technique ID listed twice is rejected" \
    techniques '["T-4001", "T-4001"]' '$.scanSummary.techniques'
expect_invalid "a technique ID with three digits is rejected" \
    techniques '["T-401"]' '$.scanSummary.techniques[0]'
expect_invalid "a technique ID in lower case is rejected" \
    techniques '["t-4001"]' '$.scanSummary.techniques[0]'
expect_invalid "a technique ID without its T- prefix is rejected" \
    techniques '["T-4001", "4001"]' '$.scanSummary.techniques[1]'

# --- the scanSummary integers stay within 2^53 - 1 (core.md §1.3a.2 rule 3) --

expect_valid "criticalFindings 9007199254740991, the largest rule 3 allows, is valid" \
    criticalFindings '9007199254740991'
expect_invalid "criticalFindings 9007199254740992 is rejected" \
    criticalFindings '9007199254740992' '$.scanSummary.criticalFindings'
expect_invalid "highFindings 1000000000000000000000 is rejected" \
    highFindings '1000000000000000000000' '$.scanSummary.highFindings'

# --- the rest of scanSummary stays closed ------------------------------------

expect_invalid "a scanSummary member the schema does not define is rejected" \
    findings '["T-4001"]' '$.scanSummary'

# --- scripts/test_schema.py leaves the working tree clean -------------------
# It imports validate_examples from scripts/. Run it in a scratch copy of the
# files it reads, without -B and with the bytecode variables unset, and assert
# that it passes and writes no scripts/__pycache__/ that a broad add would stage.

T="$(mktemp -d)"
cp -R "$REPO/scripts" "$REPO/schemas" "$REPO/core.md" "$T/"
rm -rf "$T/scripts/__pycache__"
if ! env -u PYTHONDONTWRITEBYTECODE -u PYTHONPYCACHEPREFIX \
        python3 "$T/scripts/test_schema.py" > /dev/null 2>&1; then
    not_ok "scripts/test_schema.py passes in a scratch copy" "it exited non-zero"
elif [ -e "$T/scripts/__pycache__" ]; then
    not_ok "scripts/test_schema.py writes no scripts/__pycache__/" \
        "found: $(cd "$T" && find scripts/__pycache__ | tr '\n' ' ')"
else
    ok "scripts/test_schema.py writes no scripts/__pycache__/"
fi
rm -rf "$T"

# --- summary ----------------------------------------------------------------

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d of %d test(s) failed\n' "$FAILED" "$COUNT"
    exit 1
fi
printf '# %d test(s) passed\n' "$COUNT"
