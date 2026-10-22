#!/usr/bin/env bash
# Tests for scripts/check_tbs_member_names.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree, a core.md section 1.3a.2 beside a copy of the credential schema, and
# asserted to exit 1 naming the file, the line and the rule; the delivered tree
# itself is asserted to exit 0. Shell rather than pytest so it runs with nothing
# installed: bash and python3 are all this needs.
#
#   bash scripts/test_tbs_member_names.sh
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

run_check() {  # run_check <root> [extra argument]...
    local root="$1"
    shift
    python3 -B "$REPO/scripts/check_tbs_member_names.py" --root "$root" "$@" > "$OUT" 2>&1
}

expect_pass() {  # expect_pass <leaf name> <root>
    local name="$1" rc
    run_check "$2"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        ok "$name"
    else
        not_ok "$name" "expected exit 0, got $rc: $(head -c 600 "$OUT" | tr '\n' ' ')"
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

# expect_usage <leaf name> <root> <text> [extra argument]...: exit 2 and text reported
expect_usage() {
    local name="$1" root="$2" text="$3" rc
    shift 3
    run_check "$root" "$@"
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

# Rule 1 as core.md states the member set of behavioralProfile and its outcome, on one line.
RULE1='**Canonical empties are always present.** A present `behavioralProfile` is well formed only when it is a JSON object whose member names are exactly `checksum`, `generatedAt` and `observationDays`. A verifier MUST reject a credential whose `behavioralProfile` is present and not well formed, as a signature failure (`SIGNATURE_INVALID`).'

# Rule 2 as core.md stated it before it named the members a scanSummary may hold.
RULE2_BEFORE='**`scanSummary` is always a full object.** All six members
   (`hma`, `criticalFindings`, `highFindings`, `secretless`, `cryptoServe`,
   `oasbLevel`) MUST be present, zero-valued where unknown (`""` for the string
   members, `0` for the integer members). `scanSummary` MUST NOT be `null`.
   A verifier MUST reject a credential whose `scanSummary` is not an object, or
   holds any of the six members outside its type, as a signature failure
   (`SIGNATURE_INVALID`): such a member has no value in the projection, so no
   signature covers the credential. An absent or `null` member is the zero value
   (above); this rule bites only a member that is present and the wrong type.
   Its optional `techniques` member is not one of the six; rule 6 governs it.'

# The sentences core.md adds to rule 2: the member set, and the outcome for any other member.
CLOSES='The member names a `scanSummary` may hold are exactly `hma`,
   `criticalFindings`, `highFindings`, `secretless`, `cryptoServe`, `oasbLevel`
   and `techniques`, compared exactly (a name that differs in case is a
   different member), and an issuer MUST NOT emit a `scanSummary` member with
   any other name.'
REJECTS='A verifier MUST reject a credential whose `scanSummary`
   holds a member with any other name as a signature failure
   (`SIGNATURE_INVALID`), as it does for a `behavioralProfile` whose member
   names are not exactly its three (rule 1).'
RULE2="**\`scanSummary\` is always a full object.** $CLOSES $REJECTS"

UNSTATED='[unstated] section 1.3a.2 does not say which members'
OUTCOME='[outcome] section 1.3a.2 names the members'

# tree <name> <rule 2 text, or empty for none> [included keys] [rule 1 text]
#   -> path to a scratch tree
# core.md: the section 1.3a.2 heading on line 3, the included keys on lines 8-11
# (behavioralProfile and scanSummary on line 10), rule 1 on line 14 and rule 2
# from line 15; section 1.3a.3 follows. An empty rule 1 text leaves rule 1 out.
tree() {
    local t="$TMP/$1" keys="${3:-$KEYS}" rule1="${4-$RULE1}"
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
            printf '2. %s\n' "$2"
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

# --- the delivered tree -----------------------------------------------------

expect_pass "the delivered core.md and schema pass" "$REPO"

# --- unstated ---------------------------------------------------------------

T="$(tree before "$RULE2_BEFORE")"
expect_fail "rule 2 as core.md stated it before, silent on a scanSummary member outside the six and techniques, fails for scanSummary alone" \
    "$T" "core.md:10 $UNSTATED"' `scanSummary` may hold' "!$UNSTATED"' `behavioralProfile`' \
    "!$OUTCOME"

T="$(tree rule2 "$RULE2")"
expect_pass "the rule 2 sentences core.md adds, wrapped across lines, pass" "$T"

T="$(tree rule2-in-full "$RULE2_BEFORE $CLOSES $REJECTS")"
expect_pass "the added sentences pass after the earlier rule 2 text, as core.md places them" "$T"

T="$(tree no-rule1 "$RULE2" '' '')"
expect_fail "a section without the rule 1 member set fails for behavioralProfile" "$T" \
    "core.md:10 $UNSTATED"' `behavioralProfile` may hold' "!$UNSTATED"' `scanSummary`'

T="$(tree no-techniques "**\`scanSummary\` is always a full object.** The member names a \`scanSummary\` may hold are exactly \`hma\`, \`criticalFindings\`, \`highFindings\`, \`secretless\`, \`cryptoServe\` and \`oasbLevel\`. $REJECTS")"
expect_fail "a member set that leaves out techniques, a member the schema lists, fails" "$T" \
    "core.md:10 $UNSTATED"' `scanSummary` may hold' \
    '`criticalFindings`, `cryptoServe`, `highFindings`, `hma`, `oasbLevel`, `secretless`, `techniques`'

T="$(tree no-closure "**\`scanSummary\` is always a full object.** A \`scanSummary\` holds \`hma\`, \`criticalFindings\`, \`highFindings\`, \`secretless\`, \`cryptoServe\`, \`oasbLevel\` and \`techniques\`. $REJECTS")"
expect_fail "a sentence that lists the members but does not close the set does not count" "$T" \
    "core.md:10 $UNSTATED"' `scanSummary` may hold'

T="$(tree none-of "**\`scanSummary\` is always a full object.** A verifier MUST reject a credential whose \`scanSummary\` holds a member whose name is none of \`hma\`, \`criticalFindings\`, \`highFindings\`, \`secretless\`, \`cryptoServe\`, \`oasbLevel\` and \`techniques\`, as a signature failure (\`SIGNATURE_INVALID\`).")"
expect_pass "\"none of\" closes the set, and one sentence may state both the set and the outcome" "$T"

T="$(tree no-backticks "**\`scanSummary\` is always a full object.** The member names a scanSummary may hold are exactly hma, criticalFindings, highFindings, secretless, cryptoServe, oasbLevel and techniques. $REJECTS")"
expect_fail "members named without backticks are not read" "$T" "core.md:10 $UNSTATED"' `scanSummary` may hold'

T="$(tree split "**\`scanSummary\` is always a full object.** Its members are \`hma\`, \`criticalFindings\`, \`highFindings\`, \`secretless\`, \`cryptoServe\`, \`oasbLevel\` and \`techniques\`. A \`scanSummary\` holds exactly those. $REJECTS")"
expect_fail "the members in one sentence and the closing word in the next do not count" "$T" \
    "core.md:10 $UNSTATED"' `scanSummary` may hold'

T="$(tree outside '')"
printf '\n%s %s\n' "$CLOSES" "$REJECTS" >> "$T/core.md"
expect_fail "a statement outside section 1.3a.2 does not count" "$T" \
    "core.md:10 $UNSTATED"' `scanSummary` may hold'

T="$(tree fenced $'Example:\n\n```\n'"$CLOSES $REJECTS"$'\n```')"
expect_fail "a statement in a fenced code block is not read" "$T" \
    "core.md:10 $UNSTATED"' `scanSummary` may hold'

# --- outcome ----------------------------------------------------------------

T="$(tree no-outcome "**\`scanSummary\` is always a full object.** $CLOSES")"
expect_fail "a member set with no outcome for any other member fails" "$T" \
    "core.md:15 $OUTCOME"' `scanSummary` may hold' "!$UNSTATED"

T="$(tree outcome-elsewhere "**\`scanSummary\` is always a full object.** $CLOSES"$'\n3. '"$REJECTS")"
expect_fail "an outcome in another rule does not count for the rule that states the set" "$T" \
    "core.md:15 $OUTCOME"' `scanSummary` may hold'

T="$(tree reject-only "**\`scanSummary\` is always a full object.** $CLOSES A verifier MUST reject a credential whose \`scanSummary\` holds a member with any other name.")"
expect_fail "an outcome that says reject but names no SIGNATURE_INVALID does not count" "$T" \
    "core.md:15 $OUTCOME"' `scanSummary` may hold'

T="$(tree invalid-only "**\`scanSummary\` is always a full object.** $CLOSES A \`scanSummary\` member with any other name is \`SIGNATURE_INVALID\`.")"
expect_fail "an outcome that names SIGNATURE_INVALID but does not say reject does not count" "$T" \
    "core.md:15 $OUTCOME"' `scanSummary` may hold'

T="$(tree outcome-unnamed "**\`scanSummary\` is always a full object.** $CLOSES A verifier MUST reject such a credential as a signature failure (\`SIGNATURE_INVALID\`).")"
expect_fail "an outcome sentence that does not name scanSummary in backticks does not count" "$T" \
    "core.md:15 $OUTCOME"' `scanSummary` may hold'

T="$(tree verbatim "**\`scanSummary\` is always a full object.** $CLOSES A \`scanSummary\` member with any other name MUST be included in the TBS verbatim.")"
expect_pass "an outcome that includes any other member verbatim counts" "$T"

# --- the schema and the included keys decide the objects --------------------

T="$(tree new-member "$RULE2")"
schema_set "$T" '{"type": "string"}' properties scanSummary properties scanner
expect_fail "a member the schema adds to scanSummary fails until the member set names it" "$T" \
    "core.md:10 $UNSTATED"' `scanSummary` may hold' '`scanner`'

T="$(tree open-object "")"
schema_set "$T" 'true' properties scanSummary additionalProperties
expect_pass "a scanSummary the schema leaves open is not a closed object" "$T"

T="$(tree not-included "" 'atcVersion, agentId, behavioralProfile, trustScore')"
expect_pass "a closed object the included keys leave out is not read" "$T"

T="$(tree through-ref "$RULE2_BEFORE")"
schema_set "$T" '{"type": "object", "properties": {"hma": {"type": "string"}}, "additionalProperties": false}' \
    '$defs' scan
schema_set "$T" '{"$ref": "#/$defs/scan"}' properties scanSummary
expect_fail "a closed object reached through a local \$ref is read" "$T" \
    "core.md:10 $UNSTATED"' `scanSummary` may hold: no sentence of the section names `scanSummary` and each of `hma` in backticks'

T="$(tree no-closed "$RULE2")"
printf '{"properties": {"scanSummary": {"type": "object"}, "behavioralProfile": {"type": ["object", "null"]}}}\n' \
    > "$T/schemas/atx-credential-v1.1.schema.json"
expect_fail "a schema that types no TBS key as a closed object fails instead of passing" "$T" \
    "core.md:3 [none]"

# --- the anchors ------------------------------------------------------------

T="$(tree no-section "$RULE2")"
printf '# ATX\n\n%s %s\n' "$CLOSES" "$REJECTS" > "$T/core.md"
expect_fail "a core.md without a section 1.3a.2 heading fails" "$T" "no section 1.3a.2 heading"

T="$(tree no-keys "$RULE2")"
printf '# ATX\n\n#### 1.3a.2 JCS form\n\nThe TBS projects the credential.\n\n2. %s\n' "$RULE2" \
    > "$T/core.md"
expect_fail "a section 1.3a.2 that lists no included keys fails" "$T" "core.md:3 [keys]"

T="$(tree no-core "$RULE2")"
rm "$T/core.md"
expect_fail "a tree without core.md fails" "$T" "core.md not found"

T="$(tree no-schema "$RULE2")"
rm "$T/schemas/atx-credential-v1.1.schema.json"
expect_fail "a tree without the credential schema fails" "$T" \
    "schemas/atx-credential-v1.1.schema.json not found"

T="$(tree core-latin1 "$RULE2")"
printf 'Caf\xe9.\n' >> "$T/core.md"
expect_fail "a core.md that is not UTF-8 fails" "$T" "core.md cannot be read as UTF-8 text"

T="$(tree schema-not-json "$RULE2")"
printf '{"properties": \n' > "$T/schemas/atx-credential-v1.1.schema.json"
expect_fail "a schema that is not JSON fails" "$T" \
    "schemas/atx-credential-v1.1.schema.json cannot be read as JSON"

expect_usage "an unknown option is a usage error" "$REPO" "unrecognized arguments" --no-such-option

# --- summary ----------------------------------------------------------------

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d of %d test(s) failed\n' "$FAILED" "$COUNT"
    exit 1
fi
printf '# %d test(s) passed\n' "$COUNT"
