#!/usr/bin/env bash
# Tests for scripts/check_profile_forms.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree, a core.md with a section 1.3a.2 beside a copy of the credential schema,
# and asserted to exit 1 naming the file, the line and the rule; the delivered
# tree itself is asserted to exit 0. Shell rather than pytest so it runs with
# nothing installed: bash and python3 are all this needs.
#
#   bash scripts/test_profile_forms.sh
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

run_check() {  # run_check <root> [extra argument]
    python3 -B "$REPO/scripts/check_profile_forms.py" --root "$1" ${2:+"$2"} > "$OUT" 2>&1
}

expect_pass() {  # expect_pass <leaf name> <root>
    local name="$1" rc
    run_check "$2"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        ok "$name"
    else
        not_ok "$name" "expected exit 0, got $rc: $(head -c 900 "$OUT" | tr '\n' ' ')"
    fi
}

# expect_fail <leaf name> <root> <text>...
# Exit 1 and every text reported; a text that starts with ! must not be reported.
expect_fail() {
    local name="$1" root="$2" rc needle
    shift 2
    run_check "$root"
    rc=$?
    if [ "$rc" -ne 1 ]; then
        not_ok "$name" "expected exit 1, got $rc: $(head -c 900 "$OUT" | tr '\n' ' ')"
        return
    fi
    for needle in "$@"; do
        case "$needle" in
            '!'*)
                if grep -qF -- "${needle#!}" "$OUT"; then
                    not_ok "$name" "'${needle#!}' reported: $(head -c 900 "$OUT" | tr '\n' ' ')"
                    return
                fi
                ;;
            *)
                if ! grep -qF -- "$needle" "$OUT"; then
                    not_ok "$name" "exit 1 but '$needle' not reported: $(head -c 900 "$OUT" | tr '\n' ' ')"
                    return
                fi
                ;;
        esac
    done
    ok "$name"
}

# tree <name> <rule 1> [text after rule 3] -> path to a scratch tree
# core.md: section 1.3 step 2 on lines 5-6, the section 1.3a.2 heading on line 8,
# rule 1 from line 12, rules 2 and 3 after it, then the optional text, still in
# section 1.3a.2, and section 1.3a.3. Text appended to the file lands in 1.3a.3.
tree() {
    local t="$TMP/$1"
    mkdir -p "$t/schemas"
    cp "$REPO/schemas/atx-credential-v1.1.schema.json" "$t/schemas/"
    {
        printf '# ATX\n\n### 1.3 Local verification algorithm\n\n'
        printf '2. Check the validity window. The ATX is expired at the earlier of `expiresAt` and\n'
        printf '   `issuedAt` plus the seven-day credential TTL.\n\n'
        printf '#### 1.3a.2 JCS form\n\nDeterminism rules:\n\n'
        printf '%s\n' "$2"
        printf '2. **`scanSummary` is always a full object.** All six members are present.\n'
        printf '3. **`trustScore` is string-encoded.** The projection writes it as a string.\n\n'
        if [ -n "${3-}" ]; then
            printf '%s\n\n' "$3"
        fi
        printf '#### 1.3a.3 Cross-implementation byte agreement\n\nThe vectors pin the bytes.\n'
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
    node = node.setdefault(key, {})
node[keys[-1]] = value
with open(path, "w", encoding="utf-8") as f:
    json.dump(schema, f, indent=2)
PYEOF
}

# Rule 1 as it read before it stated the forms: lines 12-18, the deferrals on 14 and 16.
OLD='1. **Canonical empties are always present.** A present `behavioralProfile` is
   well formed only when `checksum` is a JSON string, `generatedAt` is a JSON
   string in the RFC 3339 `date-time` form decided as the verifier decides
   `issuedAt` and `expiresAt` (§1.3 step 2), and `observationDays` is a JSON
   number the verifier reads as an integer, decided as it reads `trustLevel`.
   A well-formed profile is projected with `generatedAt` written in UTC to
   whole seconds (`YYYY-MM-DDTHH:MM:SSZ`).'

# Rule 1 stating both forms: lines 12-15, the date-time bullet 16-18, the integer bullet 19-20.
HEAD='1. **Canonical empties are always present.** A present `behavioralProfile` is
   well formed only when `checksum` is a JSON string, `generatedAt` is a JSON
   string in the date-time form and `observationDays` is a JSON number in the
   integer form, both stated in the bullets below.'
DATETIME='   - The date-time form. `generatedAt` matches the `date-time` production of
     RFC 3339 §5.6, with optional fractional seconds and then `Z` or a numeric
     offset.'
INTEGER='   - The integer form. `observationDays` is a JSON number written with neither
     a fraction part nor an exponent part.'
NEW="$HEAD
$DATETIME
$INTEGER"

# Statements of the forms of trustLevel and issuedAt, for deferrals to point at.
TRUST_LEVEL='`trustLevel` is a JSON number written with neither a fraction part nor an exponent part.'
ISSUED_AT='`issuedAt` matches the `date-time` production of RFC 3339 §5.6; a numeric offset is subtracted and fractional seconds are dropped.'

INTEGER_FORM='core.md:12 [integer-form] no sentence of section 1.3a.2 that names `observationDays`'
DATETIME_FORM='core.md:12 [date-time-form] no sentence of section 1.3a.2 that names `generatedAt`'
FRACTION='how it decides a number written with a fraction part (14.0)'
EXPONENT='how it decides a number written with an exponent part (1.4e1)'

# --- the delivered tree -----------------------------------------------------

expect_pass "the delivered core.md and schema pass" "$REPO"

# --- rule 1 as it read before -----------------------------------------------

T="$(tree old "$OLD")"
expect_fail "rule 1 that decides generatedAt as issuedAt and expiresAt, and observationDays as trustLevel, fails" \
    "$T" \
    'core.md:14 [deferred] decides `generatedAt` as `issuedAt` is decided, but no sentence of core.md that names `issuedAt` says what becomes of a numeric offset or what becomes of fractional seconds' \
    'core.md:14 [deferred] decides `generatedAt` as `expiresAt` is decided' \
    'core.md:16 [deferred] decides `observationDays` as `trustLevel` is decided, but no sentence of core.md that names `trustLevel` says '"$FRACTION" \
    "$DATETIME_FORM, which the schema types as a date-time string, says what becomes of a numeric offset or what becomes of fractional seconds" \
    "$INTEGER_FORM, which the schema types as integer, says $FRACTION or $EXPONENT" \
    '!(RFC 3339)'

# --- integer-form and date-time-form ----------------------------------------

T="$(tree new "$NEW")"
expect_pass "rule 1 that states both forms in bullets passes" "$T"

T="$(tree no-exponent "$HEAD
$DATETIME
   - The integer form. \`observationDays\` is a JSON number with no fraction part.")"
expect_fail "an integer form that does not say how an exponent part is decided fails" "$T" \
    "$INTEGER_FORM" "$EXPONENT" "!$FRACTION" "![date-time-form]"

T="$(tree no-offset "$HEAD
   - The date-time form. \`generatedAt\` matches RFC 3339 §5.6, with optional fractional seconds.
$INTEGER")"
expect_fail "a date-time form that does not say what becomes of an offset fails" "$T" \
    "$DATETIME_FORM" "what becomes of a numeric offset" "!what becomes of fractional seconds" \
    "!(RFC 3339)" "![integer-form]"

T="$(tree no-fraction "$HEAD
   - The date-time form. \`generatedAt\` matches RFC 3339 §5.6, then \`Z\` or a numeric offset.
$INTEGER")"
expect_fail "a date-time form that does not say what becomes of fractional seconds fails" "$T" \
    "$DATETIME_FORM" "what becomes of fractional seconds" "!what becomes of a numeric offset"

T="$(tree no-grammar "$HEAD
   - The date-time form. \`generatedAt\` has optional fractional seconds and \`Z\` or a numeric offset.
$INTEGER")"
expect_fail "a date-time form that names no RFC 3339 grammar fails" "$T" \
    "$DATETIME_FORM" "which grammar it matches (RFC 3339)" "!what becomes of"

T="$(tree spread "$HEAD
   - The date-time form. \`generatedAt\` matches RFC 3339 §5.6. The projection subtracts the
     offset of \`generatedAt\` and drops its fractional seconds.
$INTEGER")"
expect_pass "the words of a form may sit in different sentences that each name the member" "$T"

T="$(tree unnamed "$HEAD
   - The date-time form. \`generatedAt\` matches RFC 3339 §5.6. A numeric offset is
     subtracted and fractional seconds are dropped.
$INTEGER")"
expect_fail "a sentence that does not name the member does not state its form" "$T" \
    "$DATETIME_FORM" "what becomes of a numeric offset or what becomes of fractional seconds"

T="$(tree dotted "$HEAD
$DATETIME
   - The integer form. \`behavioralProfile.observationDays\` has neither a fraction nor an exponent part.")"
expect_pass "a member may be named by its dotted path" "$T"

T="$(tree letter-case "$HEAD
$DATETIME
   - The integer form. \`observationDays\` has no FRACTION part and no Exponent part.")"
expect_pass "the words are matched in any letter case" "$T"

T="$(tree later-rule "$HEAD" "The forms. \`generatedAt\` matches RFC 3339 §5.6, with fractional seconds dropped and a numeric offset subtracted. \`observationDays\` has neither a fraction part nor an exponent part.")"
expect_pass "a form stated after rule 3, still in section 1.3a.2, passes" "$T"

T="$(tree outside "$HEAD")"
printf '\n%s\n\n%s\n' \
    '`generatedAt` matches RFC 3339 §5.6, with fractional seconds dropped and a numeric offset subtracted.' \
    '`observationDays` has neither a fraction part nor an exponent part.' >> "$T/core.md"
expect_fail "a form stated outside section 1.3a.2 does not stand in for one inside it" "$T" \
    "$INTEGER_FORM" "$DATETIME_FORM"

T="$(tree fenced "$HEAD" '```
`generatedAt` matches RFC 3339 §5.6, with fractional seconds dropped and a numeric offset subtracted.
`observationDays` has neither a fraction part nor an exponent part.
```')"
expect_fail "a form stated in a fenced code block is not read" "$T" "$INTEGER_FORM" "$DATETIME_FORM"

# --- deferred ---------------------------------------------------------------

# Rule 1 deferring both members: lines 12-15, the deferrals on 14 and 15.
DEFER='1. **Canonical empties are always present.** A present `behavioralProfile` is
   well formed only when `checksum` is a JSON string, `generatedAt` is
   decided as the verifier decides `issuedAt`, and `observationDays` is
   decided as it reads `trustLevel`.'

T="$(tree defer-stated "$DEFER")"
printf '\n%s\n\n%s\n' "$TRUST_LEVEL" "$ISSUED_AT" >> "$T/core.md"
expect_pass "a deferral to a member whose form core.md states, outside section 1.3a.2 too, passes without a statement of its own" "$T"

T="$(tree defer-unstated "$DEFER")"
expect_fail "a deferral to a member whose form core.md does not state fails, and so does the member" "$T" \
    'core.md:14 [deferred] decides `generatedAt` as `issuedAt` is decided' \
    'core.md:15 [deferred] decides `observationDays` as `trustLevel` is decided' \
    "$INTEGER_FORM" "$DATETIME_FORM"

T="$(tree defer-partial "$DEFER")"
printf '\n%s\n\n%s\n' '`trustLevel` is a JSON number written with no fraction part.' "$ISSUED_AT" \
    >> "$T/core.md"
expect_fail "a deferral to a member whose form core.md states only in part fails" "$T" \
    'core.md:15 [deferred] decides `observationDays` as `trustLevel` is decided, but no sentence of core.md that names `trustLevel` says '"$EXPONENT" \
    "$INTEGER_FORM" '!`issuedAt`' "![date-time-form]"

T="$(tree defer-kind '1. **Canonical empties are always present.** A present `behavioralProfile` is
   well formed only when `checksum` is a JSON string, `generatedAt` is
   decided as the verifier decides `issuedAt`, and `observationDays` is
   decided as it reads `issuedAt`.')"
printf '\n%s\n' "$ISSUED_AT" >> "$T/core.md"
expect_fail "a deferral to a member of the other kind fails" "$T" \
    'core.md:15 [deferred] decides `observationDays` as `issuedAt` is decided, but the schema types `issuedAt` as a date-time string, not as integer' \
    "$INTEGER_FORM" "![date-time-form]"

T="$(tree defer-no-name '1. **Canonical empties are always present.** A present `behavioralProfile` is
   well formed only when `checksum` is a JSON string and `generatedAt` is
   decided as the verifier decides issuedAt.
'"$INTEGER")"
expect_fail "a deferral that names no member in backticks fails" "$T" \
    'core.md:14 [deferred] decides `generatedAt` by reference ("decided as") but names no member of the schema in backticks' \
    "$DATETIME_FORM" "![integer-form]"

T="$(tree defer-not-a-member '1. **Canonical empties are always present.** A present `behavioralProfile` is
   well formed only when `checksum` is a JSON string and `generatedAt` is
   decided as the verifier decides `windowStart`.
'"$INTEGER")"
expect_fail "a deferral to a name the schema does not define fails" "$T" \
    'core.md:14 [deferred] decides `generatedAt` by reference ("decided as") but names no member of the schema'

T="$(tree defer-verifier-reads '1. **Canonical empties are always present.** A present `behavioralProfile` is
   well formed only when `checksum` is a JSON string and `observationDays` is
   read as the verifier reads `trustLevel`.
'"$DATETIME")"
expect_fail "'as the verifier reads' is read as a deferral" "$T" \
    'core.md:14 [deferred] decides `observationDays` as `trustLevel` is decided' "$INTEGER_FORM"

T="$(tree defer-in-bullet "$HEAD
$DATETIME
   - The integer form. \`observationDays\` is decided as it reads \`trustLevel\`.")"
expect_fail "a deferral in an indented bullet of rule 1 is read" "$T" \
    'core.md:19 [deferred] decides `observationDays` as `trustLevel` is decided' "$INTEGER_FORM"

T="$(tree defer-outside-rule-1 "$NEW" "A later paragraph says \`observationDays\` is decided as it reads \`trustLevel\`.")"
expect_pass "a deferral outside rule 1 is not read" "$T"

# --- the schema decides the members -----------------------------------------

T="$(tree new-integer "$NEW")"
schema_set "$T" '{"type": "integer", "minimum": 0}' properties behavioralProfile properties observationHours
expect_fail "an integer member the schema adds to behavioralProfile needs its own form" "$T" \
    'core.md:12 [integer-form] no sentence of section 1.3a.2 that names `observationHours`' \
    '!`observationDays`'

T="$(tree new-date-time "$NEW")"
schema_set "$T" '{"type": "string", "format": "date-time"}' properties behavioralProfile properties windowEnd
expect_fail "a date-time member the schema adds to behavioralProfile needs its own form" "$T" \
    'core.md:12 [date-time-form] no sentence of section 1.3a.2 that names `windowEnd`'

T="$(tree retyped "$NEW")"
schema_set "$T" '{"type": "integer"}' properties behavioralProfile properties checksum
expect_fail "a member the schema retypes as integer needs an integer form" "$T" \
    'core.md:12 [integer-form] no sentence of section 1.3a.2 that names `checksum`'

T="$(tree not-date-time "$HEAD
$INTEGER")"
schema_set "$T" '{"type": "string"}' properties behavioralProfile properties generatedAt
expect_pass "a string member without the date-time format needs no date-time form" "$T"

T="$(tree through-ref "$NEW")"
schema_set "$T" '{"type": "object", "properties": {"generatedAt": {"type": "string", "format": "date-time"}, "observationDays": {"type": "integer"}, "observationHours": {"type": "integer"}}}' \
    '$defs' profileShape
schema_set "$T" '{"oneOf": [{"type": "null"}, {"$ref": "#/$defs/profileShape"}]}' properties behavioralProfile
expect_fail "behavioralProfile members reached through oneOf and \$ref are read" "$T" \
    'core.md:12 [integer-form] no sentence of section 1.3a.2 that names `observationHours`'

T="$(tree no-members "$NEW")"
schema_set "$T" '{"type": "object"}' properties behavioralProfile
expect_fail "a schema that defines no behavioralProfile member fails instead of passing" "$T" \
    "[members] defines no behavioralProfile member"

# --- the anchors ------------------------------------------------------------

T="$(tree no-section "$NEW")"
printf '# ATX\n\n%s\n' "$NEW" > "$T/core.md"
expect_fail "a core.md without a section 1.3a.2 heading fails" "$T" "no section 1.3a.2 heading"

T="$(tree no-rule-1 '2. **`scanSummary` is always a full object.** All six members are present.')"
expect_fail "a section 1.3a.2 without rule 1 fails" "$T" "core.md:8 [rule] section 1.3a.2 has no rule 1"

T="$(tree no-core "$NEW")"
rm "$T/core.md"
expect_fail "a tree without core.md fails" "$T" "core.md not found"

T="$(tree no-schema "$NEW")"
rm "$T/schemas/atx-credential-v1.1.schema.json"
expect_fail "a tree without the credential schema fails" "$T" \
    "schemas/atx-credential-v1.1.schema.json not found"

T="$(tree core-latin1 "$NEW")"
printf 'Caf\xe9.\n' >> "$T/core.md"
expect_fail "a core.md that is not UTF-8 fails" "$T" "core.md cannot be read as UTF-8 text"

T="$(tree schema-not-json "$NEW")"
printf '{"properties": \n' > "$T/schemas/atx-credential-v1.1.schema.json"
expect_fail "a schema that is not JSON fails" "$T" \
    "schemas/atx-credential-v1.1.schema.json cannot be read as JSON"

T="$(tree usage "$NEW")"
run_check "$T" --no-such-option
rc=$?
if [ "$rc" -eq 2 ]; then
    ok "an unknown option is a usage error"
else
    not_ok "an unknown option is a usage error" \
        "expected exit 2, got $rc: $(head -c 600 "$OUT" | tr '\n' ' ')"
fi

# --- summary ----------------------------------------------------------------

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d of %d test(s) failed\n' "$FAILED" "$COUNT"
    exit 1
fi
printf '# %d test(s) passed\n' "$COUNT"
