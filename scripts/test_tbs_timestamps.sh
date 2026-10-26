#!/usr/bin/env bash
# Tests for scripts/check_tbs_timestamps.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree, a core.md section 1.3a.2 beside a copy of the credential schema, and
# asserted to exit 1 naming the file, the line and the rule; the delivered tree
# itself is asserted to exit 0. Shell rather than pytest so it runs with nothing
# installed: bash and python3 are all this needs.
#
#   bash scripts/test_tbs_timestamps.sh
#
# Set ATX_CONFORMANCE_SUITE to a checkout of opena2a-standards/atx-conformance
# to also read the real suite's jcs-vectors; that case is skipped otherwise.
# Output is TAP-ish: one line per leaf test. Exit 0 when every test passes.

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

run_check() {  # run_check <root> <suite, or - for none> [extra argument]...
    local root="$1" suite="$2"
    shift 2
    if [ "$suite" = "-" ]; then
        python3 -B "$REPO/scripts/check_tbs_timestamps.py" --root "$root" "$@" > "$OUT" 2>&1
    else
        python3 -B "$REPO/scripts/check_tbs_timestamps.py" --root "$root" --suite "$suite" "$@" \
            > "$OUT" 2>&1
    fi
}

expect_pass() {  # expect_pass <leaf name> <root> [suite]
    local name="$1" rc
    run_check "$2" "${3:--}"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        ok "$name"
    else
        not_ok "$name" "expected exit 0, got $rc: $(head -c 600 "$OUT" | tr '\n' ' ')"
    fi
}

expect_pass_printing() {  # expect_pass_printing <leaf name> <root> <text>: exit 0, text printed
    local name="$1" rc
    run_check "$2" -
    rc=$?
    if [ "$rc" -ne 0 ]; then
        not_ok "$name" "expected exit 0, got $rc: $(head -c 600 "$OUT" | tr '\n' ' ')"
    elif ! grep -qF -- "$3" "$OUT"; then
        not_ok "$name" "exit 0 but '$3' not printed: $(head -c 600 "$OUT" | tr '\n' ' ')"
    else
        ok "$name"
    fi
}

# expect_fail <leaf name> <root> <suite, or -> <text>...
# Exit 1 and every text reported; a text that starts with ! must not be reported.
expect_fail() {
    local name="$1" root="$2" suite="$3" rc needle
    shift 3
    run_check "$root" "$suite"
    rc=$?
    if [ "$rc" -ne 1 ]; then
        not_ok "$name" "expected exit 1, got $rc: $(head -c 600 "$OUT" | tr '\n' ' ')"
        return
    fi
    for needle in "$@"; do
        case "$needle" in
            '!'*)
                if grep -qF -- "${needle#!}" "$OUT"; then
                    not_ok "$name" "'${needle#!}' reported: $(head -c 600 "$OUT" | tr '\n' ' ')"
                    return
                fi
                ;;
            *)
                if ! grep -qF -- "$needle" "$OUT"; then
                    not_ok "$name" "exit 1 but '$needle' not reported: $(head -c 600 "$OUT" | tr '\n' ' ')"
                    return
                fi
                ;;
        esac
    done
    ok "$name"
}

# expect_usage <leaf name> <root> <suite, or -> <text> [extra argument]...: exit 2 and text reported
expect_usage() {
    local name="$1" root="$2" suite="$3" text="$4" rc
    shift 4
    run_check "$root" "$suite" "$@"
    rc=$?
    if [ "$rc" -eq 2 ] && grep -qF -- "$text" "$OUT"; then
        ok "$name"
    else
        not_ok "$name" "expected exit 2 and '$text', got $rc: $(head -c 600 "$OUT" | tr '\n' ' ')"
    fi
}

KEYS='atcVersion, agentId, agentDid, publisher, publisherDid, version, contentHash,
buildAttestation, capabilities, declaredPurpose (optional, see rule 5),
behavioralProfile, scanSummary, trustScore, trustLevel, issuedAt, expiresAt,
issuerDid, issuerChain'

# The rule 1 sentence that states the projection of behavioralProfile.generatedAt,
# and the rule 7 statement for issuedAt and expiresAt as core.md states it.
RULE1='**Canonical empties are always present.** A well-formed profile is
   projected as an object of exactly those three members, with `generatedAt`
   written in UTC to whole seconds (`YYYY-MM-DDTHH:MM:SSZ`).'
RULE7='**`issuedAt` and `expiresAt` are written in UTC to whole seconds.** In the
   TBS, `issuedAt` and `expiresAt` MUST each be the instant its value in the
   credential denotes, written in UTC to whole seconds (`YYYY-MM-DDTHH:MM:SSZ`),
   as rule 1 writes `behavioralProfile.generatedAt`. For all three members the
   projection applies a time-zone offset instead of keeping it and drops a
   fractional second instead of rounding it: `2026-05-19T02:00:00.900+02:00`
   and `2026-05-18T23:30:00-00:30` are each projected as
   `2026-05-19T00:00:00Z`.'

# The rule 7 sentence that states the outcome for a timestamp outside the years
# 0000 to 9999 in UTC, as core.md states it.
RANGE='A wire value whose instant falls in UTC outside the years 0000 to 9999
   has no `YYYY-MM-DDTHH:MM:SSZ` form, and a verifier MUST reject a credential
   that carries one in any of these members rather than write a year of more
   than four digits, or a negative year, into the TBS.'

MISSING='[missing] section 1.3a.2 does not say how the TBS writes'
RANGE_FAIL='[range] section 1.3a.2 does not say what becomes of a timestamp'

# tree <name> <rule 7 statement, or empty for none> [included keys] [rule 1 text] [range text]
#   -> path to a scratch tree
# core.md: the section 1.3a.2 heading on line 3, the included keys on lines 8-11
# (behavioralProfile, issuedAt and expiresAt on line 10), rule 1 on line 14,
# rule 7 after it and the range text in a paragraph after that; section 1.3a.3
# follows. An empty rule 1 text leaves rule 1 out; an empty range text leaves
# the paragraph out.
tree() {
    local t="$TMP/$1" keys="${3:-$KEYS}" rule1="${4-$RULE1}" range="${5-$RANGE}"
    mkdir -p "$t/schemas"
    cp "$REPO/schemas/atx-credential-v1.1.schema.json" "$t/schemas/"
    {
        printf '# ATX\n\n#### 1.3a.2 JCS form\n\nThe included keys are exactly:\n\n'
        printf '```\n%s\n```\n\n' "$keys"
        if [ -n "$rule1" ]; then
            printf '1. %s\n' "$rule1"
        else
            printf '1. **Canonical empties are always present.** An absent profile is null.\n'
        fi
        if [ -n "$2" ]; then
            printf '7. %s\n' "$2"
        fi
        if [ -n "$range" ]; then
            printf '\n%s\n' "$range"
        fi
        printf '\n#### 1.3a.3 Cross-implementation byte agreement\n\nThe vectors pin the bytes.\n'
    } > "$t/core.md"
    printf '%s' "$t"
}

schema_set() {  # schema_set <tree> <JSON value> <key>...: set that member of the tree's schema
    local tree="$1" value="$2"
    shift 2
    python3 -B - "$tree/schemas/atx-credential-v1.1.schema.json" "$value" "$@" <<'PYEOF'
import json, sys
path, value, keys = sys.argv[1], json.loads(sys.argv[2]), sys.argv[3:]
with open(path, encoding="utf-8") as f:
    schema = json.load(f)
node = schema
for key in keys[:-1]:
    node = node[key]
node[keys[-1]] = value
with open(path, "w", encoding="utf-8") as f:
    json.dump(schema, f, indent=2)
PYEOF
}

# schema_ref <tree> <name, as a JSON string> <$ref> [array]: move the schema of
# properties.issuedAt in the tree's schema to $defs.<name>, as the one element of an
# array when "array" is given, and set properties.issuedAt to {"$ref": <$ref>}.
schema_ref() {
    python3 -B - "$1/schemas/atx-credential-v1.1.schema.json" "$2" "$3" "${4-}" <<'PYEOF'
import json, sys
path, name, ref, array = sys.argv[1], json.loads(sys.argv[2]), sys.argv[3], sys.argv[4]
with open(path, encoding="utf-8") as f:
    schema = json.load(f)
issued = schema["properties"]["issuedAt"]
schema["$defs"][name] = [issued] if array else issued
schema["properties"]["issuedAt"] = {"$ref": ref}
with open(path, "w", encoding="utf-8") as f:
    json.dump(schema, f, indent=2)
PYEOF
}

one_line() {  # one_line <leaf name>: the last run printed exactly one line
    if [ "$(grep -c '' "$OUT")" -eq 1 ]; then
        ok "$1"
    else
        not_ok "$1" "expected one line: $(head -c 600 "$OUT" | tr '\n' ' ')"
    fi
}

vector() {  # vector <suite> <name> <canonical TBS as JSON>: a jcs-vectors/vectors/<name>.json
    mkdir -p "$1/jcs-vectors/vectors"
    python3 -B -c '
import json, sys
print(json.dumps({"expected": {"canonicalHex": sys.argv[1].encode("utf-8").hex()}}))
' "$3" > "$1/jcs-vectors/vectors/$2.json"
}

# --- the delivered tree -----------------------------------------------------

expect_pass "the delivered core.md and schema pass" "$REPO"

if [ -n "${ATX_CONFORMANCE_SUITE-}" ]; then
    expect_pass "the real suite's jcs-vectors write each TBS timestamp in UTC to whole seconds" \
        "$REPO" "$ATX_CONFORMANCE_SUITE"
else
    skip "the real suite's jcs-vectors write each TBS timestamp in UTC to whole seconds" \
        "ATX_CONFORMANCE_SUITE not set"
fi

# --- missing ----------------------------------------------------------------

T="$(tree before '')"
expect_fail "a section that states the projection of generatedAt alone, as core.md did before rule 7, fails for issuedAt and expiresAt" \
    "$T" - \
    "core.md:10 $MISSING"' `issuedAt`, which the schema types as an RFC 3339 date-time' \
    "core.md:10 $MISSING"' `expiresAt`' \
    "!$MISSING"' `behavioralProfile.generatedAt`'

T="$(tree rule7 "$RULE7")"
expect_pass "the rule 7 statement core.md makes passes; createdAt and revokedAt, date-time members the TBS leaves out, are not required" "$T"

T="$(tree issued-only '`issuedAt` is written in UTC to whole seconds.')"
expect_fail "a statement that names issuedAt but not expiresAt fails for expiresAt alone" "$T" - \
    "core.md:10 $MISSING"' `expiresAt`' "!$MISSING"' `issuedAt`'

T="$(tree no-generated '`issuedAt` and `expiresAt` are written in UTC to whole seconds.' '' '')"
expect_fail "a section without the rule 1 sentence fails for behavioralProfile.generatedAt" "$T" - \
    "core.md:10 $MISSING"' `behavioralProfile.generatedAt`' "!$MISSING"' `issuedAt`'

T="$(tree dotted 'In the TBS, `issuedAt`, `expiresAt` and `behavioralProfile.generatedAt` are written in UTC to whole seconds.' '' '')"
expect_pass "a member may be named by its dotted path" "$T"

# --- what counts as a statement ---------------------------------------------

T="$(tree utc-only '`issuedAt` and `expiresAt` are written in UTC.')"
expect_fail "a sentence that says UTC but not whole seconds does not state the projection" "$T" - \
    "core.md:10 $MISSING"' `issuedAt`' "core.md:10 $MISSING"' `expiresAt`'

T="$(tree seconds-only '`issuedAt` and `expiresAt` are written to whole seconds.')"
expect_fail "a sentence that says whole seconds but not UTC does not state the projection" "$T" - \
    "core.md:10 $MISSING"' `issuedAt`' "core.md:10 $MISSING"' `expiresAt`'

T="$(tree two-sentences '`issuedAt` and `expiresAt` are written in UTC. They are written to whole seconds.')"
expect_fail "UTC and whole seconds in two sentences of one rule do not state the projection" "$T" - \
    "core.md:10 $MISSING"' `issuedAt`' "core.md:10 $MISSING"' `expiresAt`'

T="$(tree no-backticks 'issuedAt and expiresAt are written in UTC to whole seconds.')"
expect_fail "a member named without backticks is not read" "$T" - \
    "core.md:10 $MISSING"' `issuedAt`' "core.md:10 $MISSING"' `expiresAt`'

T="$(tree singular '`issuedAt` and `expiresAt` are written in UTC, each to the whole second.')"
expect_pass "'whole second' in the singular is read" "$T"

T="$(tree wrapped $'`issuedAt` and `expiresAt` are\n   written in UTC to whole\n   seconds.')"
expect_pass "a statement wrapped across lines is read" "$T"

T="$(tree code-span '`issuedAt` and `expiresAt` are written in UTC, as in `e.g. 2026-05-19T00:00:00Z`, to whole seconds.')"
expect_pass "a sentence does not end inside a code span" "$T"

T="$(tree outside '')"
printf '\nIn the TBS, `issuedAt` and `expiresAt` are written in UTC to whole seconds.\n' >> "$T/core.md"
expect_fail "a statement outside section 1.3a.2 does not count" "$T" - \
    "core.md:10 $MISSING"' `issuedAt`' "core.md:10 $MISSING"' `expiresAt`'

T="$(tree fenced $'Example:\n\n```\n`issuedAt` and `expiresAt` are written in UTC to whole seconds.\n```')"
expect_fail "a statement in a fenced code block is not read" "$T" - \
    "core.md:10 $MISSING"' `issuedAt`' "core.md:10 $MISSING"' `expiresAt`'

T="$(tree table $'Timestamps:\n\n| Member | Zone | Precision |\n|---|---|---|\n| `issuedAt` and `expiresAt` | UTC | whole seconds |')"
expect_fail "a table cell is read as a sentence of its own" "$T" - \
    "core.md:10 $MISSING"' `issuedAt`' "core.md:10 $MISSING"' `expiresAt`'

# --- range: a timestamp outside the years 0000 to 9999 in UTC --------------

T="$(tree no-range "$RULE7" '' "$RULE1" '')"
expect_fail "a section that states the projection but no outcome for a year outside 0000 to 9999, as core.md did before, fails" \
    "$T" - "core.md:3 $RANGE_FAIL" "!$MISSING"

T="$(tree range-in-rule7 "$RULE7 $RANGE" '' "$RULE1" '')"
expect_pass "the range sentence inside rule 7 is read" "$T"

T="$(tree range-no-reject "$RULE7" '' "$RULE1" \
    'A wire value whose instant falls in UTC outside the years 0000 to 9999 is written with five digits.')"
expect_fail "a range sentence that does not say reject states no refusal" "$T" - "core.md:3 $RANGE_FAIL"

T="$(tree range-no-utc "$RULE7" '' "$RULE1" \
    'A verifier MUST reject a value outside the years 0000 to 9999.')"
expect_fail "a range sentence that does not say UTC does not count, since the wire year can be in range" \
    "$T" - "core.md:3 $RANGE_FAIL"

T="$(tree range-one-end "$RULE7" '' "$RULE1" \
    'A verifier MUST reject a value whose instant falls in UTC after the year 9999.')"
expect_fail "a range sentence that names one end of the years alone does not count" "$T" - \
    "core.md:3 $RANGE_FAIL"

T="$(tree range-five-digits "$RULE7" '' "$RULE1" \
    'A verifier MUST reject a value whose instant falls in UTC outside the years 00000 to 99999.')"
expect_fail "years 00000 and 99999 are not the years 0000 and 9999" "$T" - "core.md:3 $RANGE_FAIL"

T="$(tree range-split "$RULE7" '' "$RULE1" \
    'A value in UTC outside the years 0000 to 9999 has no such form. A verifier MUST reject it.')"
expect_fail "UTC and the years in one sentence and reject in the next do not count" "$T" - \
    "core.md:3 $RANGE_FAIL"

T="$(tree range-outside "$RULE7" '' "$RULE1" '')"
printf '\n%s\n' "$RANGE" >> "$T/core.md"
expect_fail "a range sentence outside section 1.3a.2 does not count" "$T" - "core.md:3 $RANGE_FAIL"

T="$(tree range-fenced "$RULE7" '' "$RULE1" $'```\nA verifier MUST reject a value in UTC outside the years 0000 to 9999.\n```')"
expect_fail "a range sentence in a fenced code block is not read" "$T" - "core.md:3 $RANGE_FAIL"

# --- the schema and the included keys decide the members --------------------

T="$(tree new-member "$RULE7")"
schema_set "$T" '{"type": "string", "format": "date-time"}' properties scanSummary properties scannedAt
expect_fail "a date-time member the schema adds to scanSummary fails until a statement names it" \
    "$T" - "core.md:10 $MISSING"' `scanSummary.scannedAt`' "!$MISSING"' `issuedAt`'

T="$(tree new-member-named "$RULE7 \`scannedAt\` is also written in UTC to whole seconds.")"
schema_set "$T" '{"type": "string", "format": "date-time"}' properties scanSummary properties scannedAt
expect_pass "a date-time member the schema adds passes once a statement names it" "$T"

T="$(tree through-ref "$RULE7")"
schema_set "$T" '{"type": "string", "format": "date-time"}' '$defs' declaredPurpose properties declaredAt
expect_fail "a date-time member reached through oneOf and \$ref is a member the section names" \
    "$T" - "core.md:9 $MISSING"' `declaredPurpose.declaredAt`'

T="$(tree created-included "$RULE7" "$KEYS, createdAt")"
expect_fail "a date-time key added to the included keys is a member the section names" "$T" - \
    "core.md:11 $MISSING"' `createdAt`'

T="$(tree no-date-time "$RULE7")"
printf '{"properties": {"issuedAt": {"type": "string"}, "expiresAt": {"type": "string"}}}\n' \
    > "$T/schemas/atx-credential-v1.1.schema.json"
expect_fail "a schema that types no TBS member as a date-time fails instead of passing" "$T" - \
    "core.md:3 [none]"

# --- a $ref is a JSON pointer written as a URI fragment (RFC 6901) -----------

# The fragment is percent-decoded as UTF-8, "~1" and "~0" in a reference token read
# as "/" and "~", and a token applied to an array names the element at that index.
# Each $ref below leads to the schema of issuedAt, so the check passes and names
# the three timestamps the delivered schema types.
THREE='each of the 3 TBS member(s) the schema types as a date-time (behavioralProfile.generatedAt, expiresAt, issuedAt)'

T="$(tree ref-tilde-one "$RULE7")"
schema_ref "$T" '"time/stamp"' '#/$defs/time~1stamp'
expect_pass_printing "a \$ref that writes the \"/\" of a \$defs name as ~1 is followed" "$T" "$THREE"

T="$(tree ref-tilde-zero "$RULE7")"
schema_ref "$T" '"time~stamp"' '#/$defs/time~0stamp'
expect_pass_printing "a \$ref that writes the \"~\" of a \$defs name as ~0 is followed" "$T" "$THREE"

T="$(tree ref-tilde-order "$RULE7")"
schema_ref "$T" '"time~1stamp"' '#/$defs/time~01stamp'
expect_pass_printing "a \$ref of ~01 is read as \"~1\", not as \"/\"" "$T" "$THREE"

T="$(tree ref-percent "$RULE7")"
schema_ref "$T" '"time stamp"' '#/$defs/time%20stamp'
expect_pass_printing "a \$ref that percent-encodes the space of a \$defs name is followed" "$T" "$THREE"

T="$(tree ref-percent-utf8 "$RULE7")"
schema_ref "$T" '"timeé"' '#/$defs/time%C3%A9'
expect_pass_printing "a \$ref that percent-encodes the UTF-8 octets of a \$defs name is followed" "$T" "$THREE"

T="$(tree ref-percent-once "$RULE7")"
schema_ref "$T" '"time%41"' '#/$defs/time%2541'
expect_pass_printing "a \$ref of %2541 is read as \"%41\", decoded once" "$T" "$THREE"

T="$(tree ref-array-index "$RULE7")"
schema_ref "$T" '"alts"' '#/$defs/alts/0' array
expect_pass_printing "a \$ref that names an array element by its index is followed" "$T" "$THREE"

# A timestamp reached through such a $ref is one the section has to name.
T="$(tree ref-tilde-one-missing '`expiresAt` is written in UTC to whole seconds.')"
schema_ref "$T" '"time/stamp"' '#/$defs/time~1stamp'
expect_fail "a timestamp behind a \$ref written with ~1 is a member the section names" "$T" - \
    "core.md:10 $MISSING"' `issuedAt`' "!$MISSING"' `expiresAt`'

# A $ref the walk cannot follow stops the check naming the member and the $ref,
# instead of dropping the member from the check.
UNREADABLE='schemas/atx-credential-v1.1.schema.json cannot be read as a JSON Schema:'

T="$(tree ref-missing "$RULE7")"
schema_set "$T" '{"$ref": "#/$defs/missing"}' properties issuedAt
expect_fail "a \$ref to a missing \$defs entry fails instead of dropping the member" "$T" - \
    "$UNREADABLE"' `issuedAt` has "$ref": "#/$defs/missing", which is not a pointer to a schema in this file' \
    '!TBS timestamps ok'
one_line "a \$ref to a missing \$defs entry is reported on one line"

T="$(tree root-ref-missing "$RULE7")"
schema_set "$T" '"#/$defs/missing"' '$ref'
expect_fail "a \$ref at the schema root to a missing \$defs entry fails naming the schema root" "$T" - \
    "$UNREADABLE"' the schema root has "$ref": "#/$defs/missing", which is not a pointer to a schema in this file' \
    '![none]'

T="$(tree ref-number "$RULE7")"
schema_set "$T" '{"$ref": 5}' properties issuedAt
expect_fail "a \$ref that is not a string fails naming the member" "$T" - \
    "$UNREADABLE"' `issuedAt` has "$ref": 5, which is not a string'

T="$(tree ref-external "$RULE7")"
schema_set "$T" '{"$ref": "https://example.com/time.json"}' properties issuedAt
expect_fail "a \$ref to an external URI fails naming the member" "$T" - \
    "$UNREADABLE"' `issuedAt` has "$ref": "https://example.com/time.json", which is not a JSON pointer into this schema ("#/...")'

T="$(tree ref-hash "$RULE7")"
schema_set "$T" '{"$ref": "#"}' properties issuedAt
expect_fail "a \$ref of \"#\" fails naming the member" "$T" - \
    "$UNREADABLE"' `issuedAt` has "$ref": "#", which is not a JSON pointer into this schema ("#/...")'

T="$(tree ref-not-schema "$RULE7")"
schema_set "$T" '{"$ref": "#/$defs/did/type"}' properties issuedAt
expect_fail "a \$ref to a value that is not a schema fails naming the member" "$T" - \
    "$UNREADABLE"' `issuedAt` has "$ref": "#/$defs/did/type", which is not a pointer to a schema in this file'

T="$(tree ref-loop "$RULE7")"
schema_set "$T" '{"$ref": "#/$defs/loopB"}' '$defs' loopA
schema_set "$T" '{"$ref": "#/$defs/loopA"}' '$defs' loopB
schema_set "$T" '{"$ref": "#/$defs/loopA"}' properties issuedAt
expect_fail "a \$ref chain that leads back to itself fails naming the member" "$T" - \
    "$UNREADABLE"' `issuedAt` has "$ref": "#/$defs/loopA", which is not a $ref chain that ends at a schema'

# A $ref to a pointer the walk already followed on the way is recursion, not a
# failure, however the $ref spells the pointer: the walk stops where the pointer
# was first followed.
T="$(tree ref-recursive "$RULE7")"
schema_set "$T" '{"type": "object", "properties": {"child": {"$ref": "#/$defs/treeNode"}}}' '$defs' treeNode
schema_set "$T" '{"$ref": "#/$defs/treeNode"}' properties scanSummary properties node
expect_pass "a recursive \$ref passes" "$T"

T="$(tree ref-recursive-respelled "$RULE7")"
schema_set "$T" '{"type": "object", "properties": {"stamp": {"type": "string", "format": "date-time"}, "child": {"$ref": "#/$defs/tree%4Eode"}}}' '$defs' treeNode
schema_set "$T" '{"$ref": "#/$defs/treeNode"}' properties scanSummary properties node
expect_fail "a recursive \$ref that percent-encodes a letter of the pointer stops the walk where it was first followed" \
    "$T" - "core.md:10 $MISSING"' `scanSummary.node.stamp`' '!`scanSummary.node.child.stamp`'

# Each $ref below is not a JSON pointer and is reported so, although $defs holds the
# name that a reading which keeps the fault as written would look up.
NOT_POINTER='which is not a JSON pointer (RFC 6901):'

T="$(tree ref-bad-tilde "$RULE7")"
schema_ref "$T" '"time~2stamp"' '#/$defs/time~2stamp'
expect_fail "a \$ref with a \"~\" followed by neither 0 nor 1 is not a JSON pointer" "$T" - \
    "$UNREADABLE"' `issuedAt` has "$ref": "#/$defs/time~2stamp", '"$NOT_POINTER"' a reference token holds a "~" that is not followed by "0" or "1"'

T="$(tree ref-bad-percent "$RULE7")"
schema_ref "$T" '"time%stamp"' '#/$defs/time%stamp'
expect_fail "a \$ref with a \"%\" not followed by two hexadecimal digits is not a JSON pointer" "$T" - \
    "$UNREADABLE"' `issuedAt` has "$ref": "#/$defs/time%stamp", '"$NOT_POINTER"' a "%" in it is not followed by two hexadecimal digits'

T="$(tree ref-bad-utf8 "$RULE7")"
schema_ref "$T" '"time�stamp"' '#/$defs/time%FFstamp'
expect_fail "a \$ref that percent-encodes octets that are not UTF-8 is not a JSON pointer" "$T" - \
    "$UNREADABLE"' `issuedAt` has "$ref": "#/$defs/time%FFstamp", '"$NOT_POINTER"' the octets it percent-encodes are not UTF-8' \
    '!Traceback'

# RFC 6901 section 4: a token applied to an array is "0" or a decimal number with no
# leading zero, and "-" names the element after the last one, which does not exist.
T="$(tree ref-array-leading-zero "$RULE7")"
schema_ref "$T" '"alts"' '#/$defs/alts/00' array
expect_fail "a \$ref whose array index has a leading zero points at nothing" "$T" - \
    "$UNREADABLE"' `issuedAt` has "$ref": "#/$defs/alts/00", which is not a pointer to a schema in this file'

T="$(tree ref-array-dash "$RULE7")"
schema_ref "$T" '"alts"' '#/$defs/alts/-' array
expect_fail "a \$ref of \"-\" into an array points at nothing" "$T" - \
    "$UNREADABLE"' `issuedAt` has "$ref": "#/$defs/alts/-", which is not a pointer to a schema in this file' \
    '!Traceback'

T="$(tree ref-array-past-end "$RULE7")"
schema_ref "$T" '"alts"' '#/$defs/alts/1' array
expect_fail "a \$ref past the last element of an array points at nothing" "$T" - \
    "$UNREADABLE"' `issuedAt` has "$ref": "#/$defs/alts/1", which is not a pointer to a schema in this file' \
    '!Traceback'

# 5,000 digits: int() raises ValueError for a string of more than 4300 digits on
# Python 3.13 and 3.14. The $ref is shown cut to 60 characters.
T="$(tree ref-array-long-index "$RULE7")"
schema_ref "$T" '"alts"' "#/\$defs/alts/$(printf '%05000d' 0 | tr 0 1)" array
expect_fail "a \$ref whose array index has 5,000 digits points at nothing" "$T" - \
    "$UNREADABLE"' `issuedAt` has "$ref": "#/$defs/alts/'"$(printf '%043d' 0 | tr 0 1)"'..., which is not a pointer to a schema in this file' \
    '!Traceback'

# --- the anchors ------------------------------------------------------------

T="$(tree no-section "$RULE7")"
printf '# ATX\n\n`issuedAt` and `expiresAt` are written in UTC to whole seconds.\n' > "$T/core.md"
expect_fail "a core.md without a section 1.3a.2 heading fails" "$T" - "no section 1.3a.2 heading"

T="$(tree no-keys "$RULE7")"
printf '# ATX\n\n#### 1.3a.2 JCS form\n\nThe TBS projects the credential.\n\n7. %s\n' "$RULE7" \
    > "$T/core.md"
expect_fail "a section 1.3a.2 that lists no included keys fails" "$T" - "core.md:3 [keys]"

T="$(tree no-core "$RULE7")"
rm "$T/core.md"
expect_fail "a tree without core.md fails" "$T" - "core.md not found"

T="$(tree no-schema "$RULE7")"
rm "$T/schemas/atx-credential-v1.1.schema.json"
expect_fail "a tree without the credential schema fails" "$T" - \
    "schemas/atx-credential-v1.1.schema.json not found"

T="$(tree core-latin1 "$RULE7")"
printf 'Caf\xe9.\n' >> "$T/core.md"
expect_fail "a core.md that is not UTF-8 fails" "$T" - "core.md cannot be read as UTF-8 text"

T="$(tree schema-not-json "$RULE7")"
printf '{"properties": \n' > "$T/schemas/atx-credential-v1.1.schema.json"
expect_fail "a schema that is not JSON fails" "$T" - \
    "schemas/atx-credential-v1.1.schema.json cannot be read as JSON"

# --- --suite: the jcs-vectors -----------------------------------------------

T="$(tree vectors "$RULE7")"
S="$TMP/suite-projected"
vector "$S" 01-profile '{"behavioralProfile":{"checksum":"sha256:00","generatedAt":"2026-05-19T00:00:00Z","observationDays":14},"expiresAt":"2099-12-31T23:59:59Z","issuedAt":"2026-05-23T00:00:00Z"}'
vector "$S" 02-no-profile '{"behavioralProfile":null,"expiresAt":"2026-05-30T00:00:00Z","issuedAt":"2026-05-23T00:00:00Z"}'
expect_pass "vectors that write each timestamp in UTC to whole seconds pass; a null behavioralProfile has no generatedAt to read" \
    "$T" "$S"

S="$TMP/suite-offset"
vector "$S" 01-offset '{"behavioralProfile":null,"expiresAt":"2026-05-30T00:00:00Z","issuedAt":"2026-05-23T02:00:00+02:00"}'
expect_fail "a vector that keeps a time-zone offset in issuedAt fails" "$T" "$S" \
    'jcs-vectors/vectors/01-offset.json [vector] holds `issuedAt` as "2026-05-23T02:00:00+02:00"'

S="$TMP/suite-fraction"
vector "$S" 01-fraction '{"behavioralProfile":null,"expiresAt":"2026-05-30T00:00:00.900Z","issuedAt":"2026-05-23T00:00:00Z"}'
expect_fail "a vector that keeps a fractional second in expiresAt fails" "$T" "$S" \
    'jcs-vectors/vectors/01-fraction.json [vector] holds `expiresAt` as "2026-05-30T00:00:00.900Z"' \
    '![vector] holds `issuedAt`'

S="$TMP/suite-generated"
vector "$S" 01-generated '{"behavioralProfile":{"checksum":"sha256:00","generatedAt":"2026-05-19T02:00:00+02:00","observationDays":14},"expiresAt":"2026-05-30T00:00:00Z","issuedAt":"2026-05-23T00:00:00Z"}'
expect_fail "a vector that keeps an offset in behavioralProfile.generatedAt fails" "$T" "$S" \
    'jcs-vectors/vectors/01-generated.json [vector] holds `behavioralProfile.generatedAt` as "2026-05-19T02:00:00+02:00"'

S="$TMP/suite-number"
vector "$S" 01-number '{"behavioralProfile":null,"expiresAt":"2026-05-30T00:00:00Z","issuedAt":1779494400}'
expect_fail "a vector that holds a timestamp as a JSON number fails" "$T" "$S" \
    'jcs-vectors/vectors/01-number.json [vector] holds `issuedAt` as 1779494400'

S="$TMP/suite-left-out"
vector "$S" 01-left-out '{"behavioralProfile":null,"expiresAt":"2026-05-30T00:00:00Z"}'
expect_fail "a vector whose TBS leaves issuedAt out fails" "$T" "$S" \
    'jcs-vectors/vectors/01-left-out.json [vector] leaves the TBS key `issuedAt` out of its TBS'

S="$TMP/suite-array"
vector "$S" 01-array '[]'
expect_fail "a vector whose canonical TBS is not a JSON object fails" "$T" "$S" \
    "jcs-vectors/vectors/01-array.json [vector] expected.canonicalHex is not a JSON object"

S="$TMP/suite-unreadable"
mkdir -p "$S/jcs-vectors/vectors"
printf '{"expected": {}}\n' > "$S/jcs-vectors/vectors/01-no-hex.json"
expect_fail "a vector without expected.canonicalHex fails" "$T" "$S" \
    "jcs-vectors/vectors/01-no-hex.json [vector] cannot read expected.canonicalHex"

S="$TMP/suite-empty"
mkdir -p "$S"
expect_fail "a suite without jcs-vectors fails instead of passing" "$T" "$S" "has no jcs-vectors"

expect_usage "a --suite that is not a directory is a usage error" "$T" "$TMP/no-such-suite" \
    "not a directory"

expect_usage "an unknown option is a usage error" "$T" - "unrecognized arguments" --no-such-option

# --- summary ----------------------------------------------------------------

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d of %d test(s) failed\n' "$FAILED" "$COUNT"
    exit 1
fi
printf '# %d test(s) passed, %d skipped\n' "$((COUNT - SKIPPED))" "$SKIPPED"
