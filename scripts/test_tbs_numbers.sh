#!/usr/bin/env bash
# Tests for scripts/check_tbs_numbers.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree, a core.md section 1.3a.2 beside a copy of the credential schema, and
# asserted to exit 1 naming the file, the line and the rule; the delivered tree
# itself is asserted to exit 0. Shell rather than pytest so it runs with nothing
# installed: bash and python3 are all this needs.
#
#   bash scripts/test_tbs_numbers.sh
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

run_check() {  # run_check <root> <suite, or - for none>
    if [ "$2" = "-" ]; then
        python3 -B "$REPO/scripts/check_tbs_numbers.py" --root "$1" > "$OUT" 2>&1
    else
        python3 -B "$REPO/scripts/check_tbs_numbers.py" --root "$1" --suite "$2" > "$OUT" 2>&1
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

KEYS='atcVersion, agentId, agentDid, publisher, publisherDid, version, contentHash,
buildAttestation, capabilities, declaredPurpose (optional, see rule 5),
behavioralProfile, scanSummary, trustScore, trustLevel, issuedAt, expiresAt,
issuerDid, issuerChain'

# The rule 3 statement as core.md states it, and as it read before it named the
# scanSummary and behavioralProfile integers.
NAMED='This makes the
   integers `trustLevel`, `scanSummary.criticalFindings` and
   `scanSummary.highFindings` (rule 2), and `behavioralProfile.observationDays`
   unless `behavioralProfile` is `null` (rule 1), the only JSON numbers in the
   TBS of a conforming credential.'
ONE='This makes
   `trustLevel` (an integer) the only JSON number in the TBS, which removes the
   RFC 8785 ECMAScript number-formatting path from cross-language scope entirely.'

# The rule 3 sentence that says what a verifier does with one of those integers
# outside the range in which implementations agree on its value.
RANGE='A verifier MUST reject a credential that carries one of these members with
   an absolute value greater than 9007199254740991, as a signature failure.'

# The rule 3 sentence that says what a verifier does with a JSON number in the
# members rules 5 and 6 carry into the TBS verbatim.
VERBATIM='A verifier MUST reject a credential that carries a JSON number in
   `declaredPurpose` or `scanSummary.techniques` written with a fraction part or
   an exponent part, or whose absolute value is greater than 9007199254740991, as
   a signature failure (`SIGNATURE_INVALID`).'

MISSING='[missing] names the only JSON numbers in the TBS but not'
UNBOUNDED='schemas/atx-credential-v1.1.schema.json [unbounded]'
NO_VERBATIM='core.md:3 [verbatim] section 1.3a.2 has no sentence that names'

# tree <name> <rule 3 statement> [included keys] -> path to a scratch tree
# core.md: the section 1.3a.2 heading on line 3, the included keys on lines 8-11,
# and the statement from line 15, after the rule 3 sentence that keeps trustScore
# a JSON number on the wire. The RANGE sentence follows the statement, or
# $RANGE_TEXT when it is set (empty for none), and the VERBATIM sentence follows
# that, or $VERBATIM_TEXT when it is set (empty for none); section 1.3a.3 follows
# rule 4.
tree() {
    local t="$TMP/$1" keys="${3:-$KEYS}" range="${RANGE_TEXT-$RANGE}"
    local verbatim="${VERBATIM_TEXT-$VERBATIM}"
    mkdir -p "$t/schemas"
    cp "$REPO/schemas/atx-credential-v1.1.schema.json" "$t/schemas/"
    {
        printf '# ATX\n\n#### 1.3a.2 JCS form\n\nThe included keys are exactly:\n\n'
        printf '```\n%s\n```\n\n' "$keys"
        printf '3. **`trustScore` is string-encoded.** The wire credential keeps `trustScore`\n'
        printf '   as a JSON number; the projection performs the conversion. %s\n' "$2"
        if [ -n "$range" ]; then
            printf '   %s\n' "$range"
        fi
        if [ -n "$verbatim" ]; then
            printf '   %s\n' "$verbatim"
        fi
        printf '4. **`issuerChain` is root-first.** Element 0 is the root authority.\n\n'
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
    node = node[key]
node[keys[-1]] = value
with open(path, "w", encoding="utf-8") as f:
    json.dump(schema, f, indent=2)
PYEOF
}

# schema_root_ref <tree> <JSON value>: move the root properties of the tree's schema
# to $defs.rootTarget, give the root a $ref to it, and set the root's own properties
# to the value.
schema_root_ref() {
    python3 -B - "$1/schemas/atx-credential-v1.1.schema.json" "$2" <<'PYEOF'
import json, sys
path, value = sys.argv[1], json.loads(sys.argv[2])
with open(path, encoding="utf-8") as f:
    schema = json.load(f)
schema.setdefault("$defs", {})["rootTarget"] = {"type": "object", "properties": schema["properties"]}
schema["$ref"] = "#/$defs/rootTarget"
schema["properties"] = value
with open(path, "w", encoding="utf-8") as f:
    json.dump(schema, f, indent=2)
PYEOF
}

# schema_deep <tree> <depth> <array|properties>: replace the string "@@DEEP@@" in the
# tree's schema, set there by schema_set or schema_root_ref, with an array nested
# <depth> deep, or with <depth> object schemas each nested in the one before through
# properties.a. The value is spliced in as text: json.dump raises RecursionError for
# one nested deeper than Python's recursion limit.
schema_deep() {
    python3 -B - "$1/schemas/atx-credential-v1.1.schema.json" "$2" "$3" <<'PYEOF'
import sys
path, depth, kind = sys.argv[1], int(sys.argv[2]), sys.argv[3]
if kind == "array":
    deep = "[" * depth + "0" + "]" * depth
else:
    deep = '{"type": "object", "properties": {"a": ' * depth + "{}" + "}}" * depth
with open(path, encoding="utf-8") as f:
    text = f.read()
with open(path, "w", encoding="utf-8") as f:
    f.write(text.replace('"@@DEEP@@"', deep, 1))
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

expect_pass "the delivered core.md, schema and Markdown pass" "$REPO"

if [ -n "${ATX_CONFORMANCE_SUITE-}" ]; then
    expect_pass "the real suite's jcs-vectors hold JSON numbers only at the members core.md names" \
        "$REPO" "$ATX_CONFORMANCE_SUITE"
else
    skip "the real suite's jcs-vectors hold JSON numbers only at the members core.md names" \
        "ATX_CONFORMANCE_SUITE not set"
fi

# --- missing ----------------------------------------------------------------

T="$(tree one "$ONE")"
expect_fail "the statement that trustLevel is the only JSON number in the TBS fails for each member it leaves out" \
    "$T" - \
    "core.md:16 $MISSING"' `scanSummary.criticalFindings`, which the TBS holds as an integer' \
    "core.md:16 $MISSING"' `scanSummary.highFindings`' \
    "core.md:16 $MISSING"' `behavioralProfile.observationDays`' \
    "!$MISSING"' `trustLevel`'

T="$(tree named "$NAMED")"
expect_pass "the statement core.md makes passes; transparencyLogIndex, an integer the TBS leaves out, is not required" "$T"

T="$(tree scan-summary-only 'This makes `trustLevel`, `scanSummary.criticalFindings` and `scanSummary.highFindings` the only JSON numbers in the TBS.')"
expect_fail "a statement that names the scanSummary integers but not behavioralProfile.observationDays fails" \
    "$T" - \
    "core.md:15 $MISSING"' `behavioralProfile.observationDays`' \
    "!$MISSING"' `scanSummary.criticalFindings`'

T="$(tree own-names 'This makes `trustLevel`, `criticalFindings`, `highFindings` and `observationDays` the only JSON numbers in the TBS.')"
expect_pass "a statement may name each member by its own name instead of its dotted path" "$T"

# --- what counts as a statement ---------------------------------------------

T="$(tree sole 'This makes `trustLevel` the sole JSON number in the to-be-signed object.')"
expect_fail "'the sole JSON number in the to-be-signed object' is read as a statement" "$T" - \
    "core.md:15 $MISSING"

T="$(tree other-than 'The TBS holds no JSON numbers other than `trustLevel`.')"
expect_fail "'no JSON numbers other than' is read as a statement" "$T" - "core.md:15 $MISSING"

T="$(tree only-integers 'The conversion leaves only integers as JSON numbers in the TBS: `trustLevel`.')"
expect_fail "'only integers as JSON numbers' is read as a statement" "$T" - "core.md:15 $MISSING"

T="$(tree not-a-statement "$NAMED")"
printf '\nThe v1.1 to-be-signed projection string-encodes `trustScore`, a 0-100 JSON number on the wire.\n\nThe TBS holds JSON numbers, and only the issuer signs it.\n' \
    >> "$T/core.md"
expect_pass "a sentence that names JSON numbers and the TBS but not which are the only ones is not read" "$T"

T="$(tree code-span 'The only JSON numbers in the TBS are `trustLevel`, `criticalFindings`, `highFindings` and, once `if p. ok` holds, `observationDays`.')"
expect_pass "a sentence does not end inside a code span" "$T"

T="$(tree fenced "$NAMED")"
printf '\n```\n%s\n```\n' 'This makes `trustLevel` the only JSON number in the TBS.' >> "$T/core.md"
expect_pass "a sentence in a fenced code block is not read" "$T"

T="$(tree table "$NAMED")"
printf '\n| Rule | Text |\n|---|---|\n| 3 | `trustLevel` is the only JSON number in the TBS. |\n' >> "$T/docs.md"
expect_fail "a table cell is read as a sentence of its own" "$T" - "docs.md:4 $MISSING"

T="$(tree other-file "$NAMED")"
mkdir -p "$T/docs"
printf '# Conformance\n\nIn the TBS, `trustLevel` is the only JSON number.\n' > "$T/docs/conformance.md"
expect_fail "a statement in another Markdown file is checked" "$T" - "docs/conformance.md:3 $MISSING"

T="$(tree history "$NAMED")"
mkdir -p "$T/errata"
printf '# Changelog\n\nRule 3 said `trustLevel` is the only JSON number in the TBS.\n' > "$T/CHANGELOG.md"
printf -- '---\nid: ATX-E-0001\n---\n\nIt says `trustLevel` is the only JSON number in the TBS.\n' > "$T/errata/ATX-E-0001.md"
expect_pass "CHANGELOG.md and errata/ are not checked" "$T"

T="$(tree not-utf8 "$NAMED")"
printf 'The only JSON number in the TBS is \xff.\n' > "$T/latin1.md"
expect_fail "a Markdown file that is not UTF-8 fails" "$T" - "latin1.md [not-utf-8]"

# --- not-a-number -----------------------------------------------------------

T="$(tree trust-score 'This makes `trustScore`, `trustLevel`, `criticalFindings`, `highFindings` and `observationDays` the only JSON numbers in the TBS.')"
expect_fail "a statement that names trustScore, which rule 3 makes a string, fails" "$T" - \
    'core.md:15 [not-a-number] names `trustScore`' "rule 3 makes it a string in the TBS"

T="$(tree log-index 'This makes `trustLevel`, `criticalFindings`, `highFindings`, `observationDays` and `transparencyLogIndex` the only JSON numbers in the TBS.')"
expect_fail "a statement that names transparencyLogIndex, which the TBS leaves out, fails" "$T" - \
    'core.md:15 [not-a-number] names `transparencyLogIndex`' "the TBS does not include it"

T="$(tree string-member 'This makes `trustLevel`, `criticalFindings`, `highFindings`, `observationDays` and `scanSummary.oasbLevel` the only JSON numbers in the TBS.')"
expect_fail "a statement that names a member of another type fails" "$T" - \
    'core.md:15 [not-a-number] names `scanSummary.oasbLevel`' "the schema types it as string"

T="$(tree wrapped $'This makes `trustLevel`, `criticalFindings`,\n   `highFindings`, `observationDays` and\n   `trustScore` the only JSON numbers in the TBS.')"
expect_fail "a name on a later line of a wrapped statement is reported at its own line" "$T" - \
    'core.md:17 [not-a-number] names `trustScore`'

# --- the schema and the included keys decide the members --------------------

T="$(tree new-integer "$NAMED")"
schema_set "$T" '{"type": "integer", "minimum": 0}' properties scanSummary properties mediumFindings
expect_fail "an integer member the schema adds to scanSummary fails the statement until it names it" \
    "$T" - "core.md:18 $MISSING"' `scanSummary.mediumFindings`'

T="$(tree string-typed "$NAMED")"
schema_set "$T" '{"type": "string"}' properties scanSummary properties criticalFindings
expect_fail "a member the statement names that the schema types as a string fails" "$T" - \
    'core.md:16 [not-a-number] names `scanSummary.criticalFindings`' "the schema types it as string"

T="$(tree through-ref "$NAMED")"
schema_set "$T" '{"type": "number"}' '$defs' declaredPurpose properties refundLimit
expect_fail "a number member reached through oneOf and \$ref is a member the statement names" \
    "$T" - "core.md:18 $MISSING"' `declaredPurpose.refundLimit`, which the TBS holds as a number'

T="$(tree log-index-included "$NAMED" "$KEYS, transparencyLogIndex")"
expect_fail "an integer key added to the included keys is a member the statement names" "$T" - \
    "core.md:18 $MISSING"' `transparencyLogIndex`'

T="$(tree unknown-key "$NAMED" "$KEYS, riskScore")"
expect_fail "an included key the schema does not define fails" "$T" - \
    'core.md:11 [keys] the TBS key `riskScore` is not a property of'

# --- unbounded: the schema keeps each of them within 2^53 - 1 ----------------

T="$(tree no-maximum "$NAMED")"
schema_set "$T" '{"type": "integer", "minimum": 0}' properties scanSummary properties criticalFindings
expect_fail "a TBS integer the schema gives no maximum fails" "$T" - \
    "$UNBOUNDED"' admits an integer above 9007199254740991 at `scanSummary.criticalFindings`' \
    '!at `scanSummary.highFindings`' "![missing]"

T="$(tree maximum-above "$NAMED")"
schema_set "$T" '{"type": "integer", "minimum": 0, "maximum": 9007199254740992}' \
    properties behavioralProfile properties observationDays
expect_fail "a maximum of 9007199254740992 fails" "$T" - \
    "$UNBOUNDED"' admits an integer above 9007199254740991 at `behavioralProfile.observationDays`'

T="$(tree maximum-string "$NAMED")"
schema_set "$T" '{"type": "integer", "minimum": 0, "maximum": "9007199254740991"}' \
    properties scanSummary properties highFindings
expect_fail "a maximum written as a string does not bound the member" "$T" - \
    "$UNBOUNDED"' admits an integer above 9007199254740991 at `scanSummary.highFindings`'

T="$(tree exclusive-maximum "$NAMED")"
schema_set "$T" '{"type": "integer", "minimum": 0, "exclusiveMaximum": 9007199254740992}' \
    properties scanSummary properties criticalFindings
expect_pass "an exclusiveMaximum of 9007199254740992 bounds the member" "$T"

T="$(tree no-minimum "$NAMED")"
schema_set "$T" '{"type": "integer", "maximum": 10}' properties scanSummary properties highFindings
expect_fail "a TBS integer the schema gives no minimum fails" "$T" - \
    "$UNBOUNDED"' admits an integer below -9007199254740991 at `scanSummary.highFindings`' \
    '!admits an integer above'

T="$(tree negative-minimum "$NAMED")"
schema_set "$T" '{"type": "integer", "minimum": -9007199254740991, "maximum": 9007199254740991}' \
    properties scanSummary properties highFindings
expect_pass "a minimum of -9007199254740991 bounds the member" "$T"

# 1 followed by 400 zeros: Python's json module reads it as an exact int, which is
# too large to convert to a float.
BEYOND_FLOAT="1$(printf '%0400d' 0)"

T="$(tree maximum-beyond-float "$NAMED")"
schema_set "$T" '{"type": "integer", "minimum": 0, "maximum": '"$BEYOND_FLOAT"'}' \
    properties behavioralProfile properties observationDays
expect_fail "a maximum of 1 followed by 400 zeros, too large for a float, fails as [unbounded]" \
    "$T" - \
    "$UNBOUNDED"' admits an integer above 9007199254740991 at `behavioralProfile.observationDays`' \
    '!admits an integer below' '!Traceback'

T="$(tree minimum-beyond-float "$NAMED")"
schema_set "$T" '{"type": "integer", "minimum": -'"$BEYOND_FLOAT"', "maximum": 10}' \
    properties scanSummary properties highFindings
expect_fail "a minimum of -1 followed by 400 zeros, too large for a float, fails as [unbounded]" \
    "$T" - \
    "$UNBOUNDED"' admits an integer below -9007199254740991 at `scanSummary.highFindings`' \
    '!admits an integer above' '!Traceback'

T="$(tree exclusive-beyond-float "$NAMED")"
schema_set "$T" '{"type": "integer", "exclusiveMinimum": -'"$BEYOND_FLOAT"', "exclusiveMaximum": '"$BEYOND_FLOAT"'}' \
    properties scanSummary properties criticalFindings
expect_fail "an exclusiveMinimum and exclusiveMaximum of minus and plus 1 followed by 400 zeros fail as [unbounded]" \
    "$T" - \
    "$UNBOUNDED"' admits an integer below -9007199254740991 at `scanSummary.criticalFindings`' \
    "$UNBOUNDED"' admits an integer above 9007199254740991 at `scanSummary.criticalFindings`' \
    '!Traceback'

T="$(tree number-typed "$NAMED")"
schema_set "$T" '{"type": "number", "minimum": 0, "maximum": 4}' properties trustLevel
expect_fail "a TBS member the schema types as number fails although it is bounded" "$T" - \
    "$UNBOUNDED"' types `trustLevel` as number'

T="$(tree ref-unbounded "$NAMED")"
schema_set "$T" '{"type": "integer", "minimum": 0}' '$defs' declaredPurpose properties refundLimit
expect_fail "an integer member reached through oneOf and \$ref is checked for its bounds" "$T" - \
    "$UNBOUNDED"' admits an integer above 9007199254740991 at `declaredPurpose.refundLimit`'

# --- range: section 1.3a.2 says a verifier rejects one outside it -----------

T="$(RANGE_TEXT='' tree no-range "$NAMED")"
expect_fail "a section 1.3a.2 that does not say what a verifier does outside the range fails" \
    "$T" - "core.md:3 [range]" "![missing]" "!$UNBOUNDED"

T="$(RANGE_TEXT='The schema bounds each of them to at most 9007199254740991.' tree no-reject "$NAMED")"
expect_fail "a sentence that says 9007199254740991 but not reject does not count" "$T" - \
    "core.md:3 [range]"

T="$(RANGE_TEXT='A verifier MUST reject an absolute value greater than 90071992547409910.' tree longer-number "$NAMED")"
expect_fail "9007199254740991 inside a longer number does not count" "$T" - "core.md:3 [range]"

T="$(RANGE_TEXT='' tree range-moved "$NAMED")"
printf '\n%s\n' "$RANGE" >> "$T/core.md"
expect_fail "the range sentence outside section 1.3a.2 does not stand in for one inside it" \
    "$T" - "core.md:3 [range]"

T="$(RANGE_TEXT='A verifier MUST reject a credential that carries a JSON number in `declaredPurpose` whose absolute value is greater than 9007199254740991.' VERBATIM_TEXT='' tree range-names-purpose "$NAMED")"
expect_fail "a sentence that says 9007199254740991 and reject but names declaredPurpose does not stand in for the range sentence" \
    "$T" - "core.md:3 [range]" "$NO_VERBATIM"' `declaredPurpose`'

# --- verbatim: a JSON number in declaredPurpose or scanSummary.techniques ----

T="$(VERBATIM_TEXT='' tree no-verbatim "$NAMED")"
expect_fail "a section 1.3a.2 that does not say what a verifier does with a JSON number in declaredPurpose or scanSummary.techniques fails for each" \
    "$T" - "$NO_VERBATIM"' `declaredPurpose` and says "fraction", "exponent", "9007199254740991", "reject" and "SIGNATURE_INVALID"' \
    "$NO_VERBATIM"' `scanSummary.techniques`' "![range]" "![missing]" "!$UNBOUNDED"

T="$(VERBATIM_TEXT='A verifier MUST reject a credential that carries a JSON number in `declaredPurpose` written with a fraction part or an exponent part, or whose absolute value is greater than 9007199254740991, as a signature failure (`SIGNATURE_INVALID`).' tree purpose-only "$NAMED")"
expect_fail "a sentence that names declaredPurpose and not scanSummary.techniques fails for scanSummary.techniques only" \
    "$T" - "$NO_VERBATIM"' `scanSummary.techniques`' "!$NO_VERBATIM"' `declaredPurpose`'

T="$(VERBATIM_TEXT='A verifier MUST reject a credential that carries a JSON number in `declaredPurpose` or `techniques` written with a fraction part or an exponent part, or whose absolute value is greater than 9007199254740991, as a signature failure (`SIGNATURE_INVALID`).' tree techniques-own-name "$NAMED")"
expect_pass "a sentence may name scanSummary.techniques by its own name" "$T"

T="$(VERBATIM_TEXT='A verifier MUST reject a credential that carries a JSON number in `declaredPurpose` or `scanSummary.techniques` written with a fractional part or an exponent part, or whose absolute value is greater than 9007199254740991, as a signature failure (`SIGNATURE_INVALID`).' tree verbatim-fractional "$NAMED")"
expect_pass "'fractional' counts as 'fraction'" "$T"

T="$(VERBATIM_TEXT='A verifier MUST reject a credential that carries a JSON number in `declaredPurpose` or `scanSummary.techniques` written with an exponent part, or whose absolute value is greater than 9007199254740991, as a signature failure (`SIGNATURE_INVALID`).' tree verbatim-no-fraction "$NAMED")"
expect_fail "a sentence that does not say fraction does not count" "$T" - \
    "$NO_VERBATIM"' `declaredPurpose`' "$NO_VERBATIM"' `scanSummary.techniques`'

T="$(VERBATIM_TEXT='A verifier MUST reject a credential that carries a JSON number in `declaredPurpose` or `scanSummary.techniques` written with a fraction part, or whose absolute value is greater than 9007199254740991, as a signature failure (`SIGNATURE_INVALID`).' tree verbatim-no-exponent "$NAMED")"
expect_fail "a sentence that does not say exponent does not count" "$T" - \
    "$NO_VERBATIM"' `declaredPurpose`' "$NO_VERBATIM"' `scanSummary.techniques`'

T="$(VERBATIM_TEXT='A verifier MUST reject a credential that carries a JSON number in `declaredPurpose` or `scanSummary.techniques` written with a fraction part or an exponent part, or whose absolute value is greater than 2^53 - 1, as a signature failure (`SIGNATURE_INVALID`).' tree verbatim-no-exact "$NAMED")"
expect_fail "a sentence that does not say 9007199254740991 does not count" "$T" - \
    "$NO_VERBATIM"' `declaredPurpose`' "$NO_VERBATIM"' `scanSummary.techniques`'

T="$(VERBATIM_TEXT='A verifier MUST NOT accept a credential that carries a JSON number in `declaredPurpose` or `scanSummary.techniques` written with a fraction part or an exponent part, or whose absolute value is greater than 9007199254740991, as a signature failure (`SIGNATURE_INVALID`).' tree verbatim-no-reject "$NAMED")"
expect_fail "a sentence that does not say reject does not count" "$T" - \
    "$NO_VERBATIM"' `declaredPurpose`' "$NO_VERBATIM"' `scanSummary.techniques`'

T="$(VERBATIM_TEXT='A verifier MUST reject a credential that carries a JSON number in `declaredPurpose` or `scanSummary.techniques` written with a fraction part or an exponent part, or whose absolute value is greater than 9007199254740991, as a signature failure.' tree verbatim-no-code "$NAMED")"
expect_fail "a sentence that does not say SIGNATURE_INVALID does not count" "$T" - \
    "$NO_VERBATIM"' `declaredPurpose`' "$NO_VERBATIM"' `scanSummary.techniques`'

T="$(VERBATIM_TEXT='A verifier MUST reject a credential that carries a JSON number in `declaredPurpose` or `scanSummary.techniques` written with a fraction part or an exponent part, as a signature failure (`SIGNATURE_INVALID`). It also rejects one whose absolute value is greater than 9007199254740991.' tree verbatim-split "$NAMED")"
expect_fail "the words split across two sentences do not count" "$T" - \
    "$NO_VERBATIM"' `declaredPurpose`' "$NO_VERBATIM"' `scanSummary.techniques`'

T="$(VERBATIM_TEXT='A verifier MUST reject a credential that carries a JSON number in declaredPurpose or scanSummary.techniques written with a fraction part or an exponent part, or whose absolute value is greater than 9007199254740991, as a signature failure (`SIGNATURE_INVALID`).' tree verbatim-bare-names "$NAMED")"
expect_fail "member names outside backticks do not count" "$T" - \
    "$NO_VERBATIM"' `declaredPurpose`' "$NO_VERBATIM"' `scanSummary.techniques`'

T="$(VERBATIM_TEXT='' tree verbatim-moved "$NAMED")"
printf '\n%s\n' "$VERBATIM" >> "$T/core.md"
expect_fail "the verbatim sentence outside section 1.3a.2 does not stand in for one inside it" \
    "$T" - "$NO_VERBATIM"' `declaredPurpose`' "$NO_VERBATIM"' `scanSummary.techniques`'

# --- absent and the anchors -------------------------------------------------

T="$(tree no-statement '')"
expect_fail "a section 1.3a.2 that names no JSON numbers of the TBS fails" "$T" - "core.md:3 [absent]"

T="$(tree moved '')"
printf 'In the TBS the only JSON numbers are `trustLevel`, `criticalFindings`, `highFindings` and `observationDays`.\n' \
    >> "$T/core.md"
expect_fail "a statement outside section 1.3a.2 does not stand in for one inside it" "$T" - \
    "core.md:3 [absent]" "![missing]"

T="$(tree no-section "$NAMED")"
printf '# ATX\n\nThe only JSON number in the TBS is `trustLevel`.\n' > "$T/core.md"
expect_fail "a core.md without a section 1.3a.2 heading fails" "$T" - "no section 1.3a.2 heading"

T="$(tree no-keys "$NAMED")"
printf '# ATX\n\n#### 1.3a.2 JCS form\n\nThe TBS projects the credential.\n\n3. %s\n' "$NAMED" > "$T/core.md"
expect_fail "a section 1.3a.2 that lists no included keys fails" "$T" - "core.md:3 [keys]"

T="$(tree no-core "$NAMED")"
rm "$T/core.md"
expect_fail "a tree without core.md fails" "$T" - "core.md not found"

T="$(tree no-schema "$NAMED")"
rm "$T/schemas/atx-credential-v1.1.schema.json"
expect_fail "a tree without the credential schema fails" "$T" - \
    "schemas/atx-credential-v1.1.schema.json not found"

T="$(tree core-latin1 "$NAMED")"
printf 'Caf\xe9.\n' >> "$T/core.md"
expect_fail "a core.md that is not UTF-8 fails" "$T" - "core.md cannot be read as UTF-8 text"

T="$(tree schema-not-json "$NAMED")"
printf '{"properties": \n' > "$T/schemas/atx-credential-v1.1.schema.json"
expect_fail "a schema that is not JSON fails" "$T" - \
    "schemas/atx-credential-v1.1.schema.json cannot be read as JSON"

# A type, oneOf, anyOf, allOf or properties of a JSON type JSON Schema does not
# allow there stops the check with a message that names the member, not with a
# traceback.
UNREADABLE='schemas/atx-credential-v1.1.schema.json cannot be read as a JSON Schema:'

T="$(tree type-number "$NAMED")"
schema_set "$T" '5' properties scanSummary properties highFindings type
expect_fail "a type that is a number fails naming the schema and the member" "$T" - \
    "$UNREADABLE"' `scanSummary.highFindings` has "type": 5, which is not a string or an array of strings' \
    '!Traceback' '![not-a-number]'

T="$(tree type-null "$NAMED")"
schema_set "$T" 'null' properties scanSummary properties highFindings type
expect_fail "a type that is null fails naming the schema and the member" "$T" - \
    "$UNREADABLE"' `scanSummary.highFindings` has "type": null, which is not a string or an array of strings' \
    '!Traceback'

T="$(tree type-array-number "$NAMED")"
schema_set "$T" '[5]' properties scanSummary properties highFindings type
expect_fail "a type that is an array holding a number fails naming the schema and the member" "$T" - \
    "$UNREADABLE"' `scanSummary.highFindings` has "type": [5], which is not a string or an array of strings' \
    '!Traceback'

T="$(tree one-of-number "$NAMED")"
schema_set "$T" '5' properties scanSummary oneOf
expect_fail "a oneOf that is a number fails naming the schema and the member" "$T" - \
    "$UNREADABLE"' `scanSummary` has "oneOf": 5, which is not an array' '!Traceback'

T="$(tree any-all-of "$NAMED")"
schema_set "$T" '{}' properties behavioralProfile anyOf
schema_set "$T" 'null' allOf
expect_fail "an anyOf and an allOf that are not arrays are each reported, the root's as the schema root" \
    "$T" - \
    "$UNREADABLE"' `behavioralProfile` has "anyOf": {}, which is not an array' \
    "$UNREADABLE"' the schema root has "allOf": null, which is not an array' '!Traceback'

T="$(tree root-properties "$NAMED")"
schema_set "$T" '5' properties
expect_fail "a properties at the schema root that is a number fails" "$T" - \
    "$UNREADABLE"' the schema root has "properties": 5, which is not an object' '!Traceback'
one_line "a properties at the schema root that is a number is reported on one line"

# The walk reads no other keyword of a node that has a $ref, so the root's own
# properties, where the included keys are looked up, is checked apart from the walk.
T="$(tree root-ref-properties "$NAMED")"
schema_root_ref "$T" '5'
expect_fail "a properties at the schema root that is a number fails when the root has a \$ref" \
    "$T" - "$UNREADABLE"' the schema root has "properties": 5, which is not an object' \
    '!Traceback' '![keys]'
one_line "a properties at the schema root that is a number beside a \$ref is reported on one line"

T="$(tree root-ref-null "$NAMED")"
schema_root_ref "$T" 'null'
expect_fail "a properties at the schema root that is null fails when the root has a \$ref" \
    "$T" - "$UNREADABLE"' the schema root has "properties": null, which is not an object' \
    '!Traceback'

T="$(tree root-ref-array "$NAMED")"
schema_root_ref "$T" '["atcVersion"]'
expect_fail "a properties at the schema root that is an array fails when the root has a \$ref, instead of being read as a list of keys" \
    "$T" - "$UNREADABLE"' the schema root has "properties": ["atcVersion"], which is not an object' \
    '![keys]'

T="$(tree member-properties "$NAMED")"
schema_set "$T" '[]' properties scanSummary properties
expect_fail "a properties that is an array fails instead of leaving that member's integers unchecked" \
    "$T" - "$UNREADABLE"' `scanSummary` has "properties": [], which is not an object'

# A $ref the walk cannot follow stops the check naming the member and the $ref,
# instead of dropping every member under it from the check.
T="$(tree root-ref-missing "$NAMED")"
schema_set "$T" '"#/$defs/missing"' '$ref'
expect_fail "a \$ref at the schema root to a missing \$defs entry fails instead of checking no member" \
    "$T" - "$UNREADABLE"' the schema root has "$ref": "#/$defs/missing", which is not a pointer to a schema in this file' \
    '!Traceback' '!TBS numbers ok'
one_line "a \$ref at the schema root to a missing \$defs entry is reported on one line"

T="$(tree member-ref-missing "$NAMED")"
schema_set "$T" '{"$ref": "#/$defs/missing"}' properties scanSummary
expect_fail "a \$ref at a member to a missing \$defs entry fails instead of leaving its integers unchecked" \
    "$T" - "$UNREADABLE"' `scanSummary` has "$ref": "#/$defs/missing", which is not a pointer to a schema in this file' \
    '!TBS numbers ok'
one_line "a \$ref at a member to a missing \$defs entry is reported on one line"

T="$(tree member-ref-number "$NAMED")"
schema_set "$T" '{"$ref": 5}' properties scanSummary
expect_fail "a \$ref that is not a string fails naming the member" "$T" - \
    "$UNREADABLE"' `scanSummary` has "$ref": 5, which is not a string'

T="$(tree member-ref-external "$NAMED")"
schema_set "$T" '{"$ref": "https://example.com/scan-summary.json"}' properties scanSummary
expect_fail "a \$ref to an external URI fails naming the member" "$T" - \
    "$UNREADABLE"' `scanSummary` has "$ref": "https://example.com/scan-summary.json", which is not a JSON pointer into this schema ("#/...")'

T="$(tree member-ref-hash "$NAMED")"
schema_set "$T" '{"$ref": "#"}' properties scanSummary
expect_fail "a \$ref of \"#\" fails naming the member" "$T" - \
    "$UNREADABLE"' `scanSummary` has "$ref": "#", which is not a JSON pointer into this schema ("#/...")'

T="$(tree member-ref-not-schema "$NAMED")"
schema_set "$T" '{"$ref": "#/$defs/did/type"}' properties scanSummary
expect_fail "a \$ref to a value that is not a schema fails naming the member" "$T" - \
    "$UNREADABLE"' `scanSummary` has "$ref": "#/$defs/did/type", which is not a pointer to a schema in this file'

T="$(tree member-ref-loop "$NAMED")"
schema_set "$T" '{"$ref": "#/$defs/loopB"}' '$defs' loopA
schema_set "$T" '{"$ref": "#/$defs/loopA"}' '$defs' loopB
schema_set "$T" '{"$ref": "#/$defs/loopA"}' properties scanSummary
expect_fail "a \$ref chain that leads back to itself fails naming the member" "$T" - \
    "$UNREADABLE"' `scanSummary` has "$ref": "#/$defs/loopA", which is not a $ref chain that ends at a schema'

# A $ref back to a node the walk is already inside is recursion, not a failure.
T="$(tree member-ref-recursive "$NAMED")"
schema_set "$T" '{"type": "object", "properties": {"child": {"$ref": "#/$defs/treeNode"}}}' '$defs' treeNode
schema_set "$T" '{"$ref": "#/$defs/treeNode"}' properties extensionTree
expect_pass "a recursive \$ref outside the TBS passes" "$T"

# --- a schema nested deeper than Python reads, writes or walks --------------

# Each stops the check with one line, not with a RecursionError traceback. The
# depth at which each limit is reached depends on the Python version and the
# stack size, so the cases are built from the deepest array json.loads reads
# here, found by bisection up to 2,000,000, and from the recursion limit.
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
# 95 of every 100 of those levels: json.loads reads it, and on Python 3.14.3 on
# macOS arm64 json.dumps cannot write it.
VALUE_DEPTH=$((LOADS_DEPTH - LOADS_DEPTH / 20))
# Twice the recursion limit: each schema nested in another is one more call.
WALK_DEPTH="$(python3 -B -c 'import sys; print(2 * sys.getrecursionlimit())')"
# The deep array cut to 60 characters: 57 of its [ and "...".
CUT_ARRAY="$(printf '%57s' '' | tr ' ' '[')..."

if [ "$LOADS_DEPTH" -lt 2000000 ]; then
    T="$(tree deep-read "$NAMED")"
    schema_set "$T" '"@@DEEP@@"' properties
    schema_deep "$T" "$((2 * LOADS_DEPTH))" array
    expect_fail "a schema nested deeper than json.loads reads fails as not JSON" "$T" - \
        "schemas/atx-credential-v1.1.schema.json cannot be read as JSON: it nests arrays or objects deeper than the json module of this Python can read" \
        '!Traceback'
    one_line "a schema nested deeper than json.loads reads is reported on one line"
else
    skip "a schema nested deeper than json.loads reads fails as not JSON" \
        "json.loads reads 2,000,000 levels here"
    skip "a schema nested deeper than json.loads reads is reported on one line" \
        "json.loads reads 2,000,000 levels here"
fi

T="$(tree deep-value "$NAMED")"
schema_set "$T" '"@@DEEP@@"' properties
schema_deep "$T" "$VALUE_DEPTH" array
expect_fail "a root properties nested deeper than json.dumps writes is shown cut to 60 characters" \
    "$T" - "$UNREADABLE"' the schema root has "properties": '"$CUT_ARRAY"', which is not an object' \
    '!Traceback'
one_line "a root properties nested deeper than json.dumps writes is reported on one line"

T="$(tree deep-value-ref "$NAMED")"
schema_root_ref "$T" '"@@DEEP@@"'
schema_deep "$T" "$VALUE_DEPTH" array
expect_fail "a root properties nested deeper than json.dumps writes is shown cut to 60 characters beside a \$ref" \
    "$T" - "$UNREADABLE"' the schema root has "properties": '"$CUT_ARRAY"', which is not an object' \
    '!Traceback' '![keys]'
one_line "a root properties nested deeper than json.dumps writes beside a \$ref is reported on one line"

# Two JSON levels per schema: the schema and its properties.
if [ "$LOADS_DEPTH" -gt $((2 * WALK_DEPTH + 100)) ]; then
    T="$(tree deep-walk "$NAMED")"
    schema_set "$T" '"@@DEEP@@"' properties scanSummary properties deep
    schema_deep "$T" "$WALK_DEPTH" properties
    expect_fail "schemas nested deeper than the walk follows fail naming the member, cut to 60 characters" \
        "$T" - "$UNREADABLE"' `scanSummary.deep.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a....` nests deeper than the check can walk' \
        '!Traceback'
    one_line "schemas nested deeper than the walk follows are reported on one line"
else
    skip "schemas nested deeper than the walk follows fail naming the member, cut to 60 characters" \
        "json.loads reads no schema nested that deep here"
    skip "schemas nested deeper than the walk follows are reported on one line" \
        "json.loads reads no schema nested that deep here"
fi

# --- --suite: the jcs-vectors -----------------------------------------------

T="$(tree vectors "$NAMED")"
S="$TMP/suite-members"
vector "$S" 01-profile '{"behavioralProfile":{"observationDays":14},"scanSummary":{"criticalFindings":0,"highFindings":0},"trustLevel":4,"trustScore":"87.500000"}'
vector "$S" 02-no-profile '{"behavioralProfile":null,"scanSummary":{"criticalFindings":1,"highFindings":3},"trustLevel":3}'
expect_pass "vectors whose JSON numbers sit at the members the statement names pass" "$T" "$S"

S="$TMP/suite-score"
vector "$S" 01-score-number '{"scanSummary":{"criticalFindings":0,"highFindings":0},"trustLevel":4,"trustScore":87.5}'
expect_fail "a vector that holds trustScore as a JSON number fails" "$T" "$S" \
    'jcs-vectors/vectors/01-score-number.json [vector] holds the JSON number 87.5 at `trustScore`'

S="$TMP/suite-exact"
vector "$S" 01-largest '{"behavioralProfile":{"observationDays":9007199254740991},"scanSummary":{"criticalFindings":0,"highFindings":0},"trustLevel":4}'
expect_pass "a vector that holds 9007199254740991 at one of those members passes" "$T" "$S"

S="$TMP/suite-beyond"
vector "$S" 01-above '{"scanSummary":{"criticalFindings":9007199254740993,"highFindings":0},"trustLevel":4}'
vector "$S" 02-exponent '{"behavioralProfile":{"observationDays":1e+21},"trustLevel":4}'
expect_fail "a vector that holds an integer above 9007199254740991 at one of those members fails" \
    "$T" "$S" \
    'jcs-vectors/vectors/01-above.json [vector] holds the JSON number 9007199254740993 at `scanSummary.criticalFindings`, whose absolute value is greater than 9007199254740991' \
    'jcs-vectors/vectors/02-exponent.json [vector] holds the JSON number 1e+21 at `behavioralProfile.observationDays`'

S="$TMP/suite-array"
vector "$S" 01-array '{"capabilities":["db:read",7],"trustLevel":4}'
expect_fail "a JSON number inside an array is reported at the array's member" "$T" "$S" \
    'jcs-vectors/vectors/01-array.json [vector] holds the JSON number 7 at `capabilities`'

S="$TMP/suite-unreadable"
mkdir -p "$S/jcs-vectors/vectors"
printf '{"expected": {}}\n' > "$S/jcs-vectors/vectors/01-no-hex.json"
expect_fail "a vector without expected.canonicalHex fails" "$T" "$S" \
    "jcs-vectors/vectors/01-no-hex.json [vector] cannot read expected.canonicalHex"

S="$TMP/suite-empty"
mkdir -p "$S"
expect_fail "a suite without jcs-vectors fails instead of passing" "$T" "$S" "has no jcs-vectors"

run_check "$T" "$TMP/no-such-suite"
rc=$?
if [ "$rc" -eq 2 ] && grep -qF "not a directory" "$OUT"; then
    ok "a --suite that is not a directory is a usage error"
else
    not_ok "a --suite that is not a directory is a usage error" \
        "expected exit 2, got $rc: $(head -c 600 "$OUT" | tr '\n' ' ')"
fi

# --- summary ----------------------------------------------------------------

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d of %d test(s) failed\n' "$FAILED" "$COUNT"
    exit 1
fi
printf '# %d test(s) passed, %d skipped\n' "$((COUNT - SKIPPED))" "$SKIPPED"
