#!/usr/bin/env bash
# Tests for scripts/check_pointers.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree and asserted to exit 1 naming the file, the line and the rule; the
# delivered tree itself is asserted to exit 0. Shell rather than pytest so it
# runs with nothing installed: bash and python3 are all this needs.
#
#   bash scripts/test_pointers.sh
#
# Output is TAP-ish: one line per leaf test. Exit 0 when every test passes.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ATP='ATP-SPEC v1.0.0-rc1 §8.1'
SCHEMA='https://specs.opena2a.org/schemas/atp/revocation-list-v1.schema.json'
HMA_README='https://github.com/opena2a-org/hackmyagent/blob/main/README.md'
AIP_SPEC='https://github.com/opena2a-standards/agent-identity-protocol/blob/main/AIP-SPEC.md'
HMA_ROW="Its static, semantic and adversarial checks gate trust level; the [HackMyAgent README]($HMA_README) states how many of each it ships."
AIM_ROW="It computes the trust score specified in [AIP §6.1]($AIP_SPEC), a multi-factor algorithm, which feeds into ATX trust score."

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
    python3 -B "$REPO/scripts/check_pointers.py" --root "$1" > "$OUT" 2>&1
}

new_tree() {  # new_tree <name> -> path to an empty scratch tree
    mkdir -p "$TMP/$1"
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

# write_core <root> <item 5 references> <section 3.3 references>
#            [<section 1.5 text>] [<section 10 authorization bullet text>]
#            [<section 8 HackMyAgent row text>] [<section 8 AIM row text>]
#            [<section 8 Build plugin row text>]
# Sections 1.5, 10 and 8 follow section 4 so the line numbers above them stay
# put; the check finds a section by its opening line, wherever it sits. In the
# section 8 table the HackMyAgent row is line 36 and the AIM row line 38. A tree
# with no README.md also gets the default one from write_readme.
write_core() {
    local purpose="${4-Neither is permission: that is a broker policy decision under AAP.}"
    local authz="${5-AAP is the authorization layer. ATX presents the credential.}"
    local hma="${6-$HMA_ROW}"
    local aim="${7-$AIM_ROW}"
    local build="${8-Translates every CI build into a build attestation and ATX request.}"
    cat > "$1/core.md" <<EOF
## 2. The Agent Trust Protocol (ATP)

4. **The federation protocol.** How nodes propagate revocations.
5. **The revocation list format.** $2

Text after the list.

## 3. The five planes

### 3.3 Revocation flow

Revocation speed is the measure.

$3

1. Revocation trigger fires.

## 4. Developer reported trust

$ATP and $SCHEMA, cited outside both sections.

### 1.5 Declared purpose (optional)

$purpose

## 10. What ATX is not

* **ATX is not an identity system.** AIM is.
* **ATX is not a runtime authorization system.** $authz
* **ATX is not a centralized database.** AAP is named in this bullet, not the one above.

## 8. Product integration map

| Product | Role | What it contributes |
|---|---|---|
| HackMyAgent | The scanner at issuance | $hma |
| Build plugin | The CA interface | $build |
| AIM | Identity issuance and runtime enforcement | $aim |
| CryptoServe | PQC hygiene at issuance | ML-DSA-65 signature on every ATX. OASB levels L1, L2, L3. |
EOF
    [ -e "$1/README.md" ] || write_readme "$1"
}

# write_readme <root> [<use case 3 "where it stops" text>]
write_readme() {
    local stops="${2-They are not permission. That is a broker policy decision under AAP.}"
    cat > "$1/README.md" <<EOF
# atx-spec

## Use cases

### A stranger's agent calls you and you cannot phone home on every request

AAP is named here, before use case 3.

### An auditor asks what each agent was allowed to attempt, and what scanned it

Where it stops today: $stops

## Contributing

AAP is named here too, after use case 3.
EOF
}

# --- the delivered tree -----------------------------------------------------

expect_pass "the repository's own core.md and README.md pass" "$REPO"

# --- pointer ----------------------------------------------------------------

T="$(new_tree both)"
write_core "$T" "Specified in $ATP, schema \`$SCHEMA\`." "Wire format: $ATP; schema \`$SCHEMA\`."
expect_pass "both sections citing both references pass" "$T"

T="$(new_tree section-3-3-bare)"
write_core "$T" "Specified in $ATP, schema \`$SCHEMA\`." "No pointer here."
expect_fail "section 3.3 without the pointer fails, even when a later section has it" \
    "$T" pointer "core.md:10"

T="$(new_tree section-3-3-no-schema)"
write_core "$T" "Specified in $ATP, schema \`$SCHEMA\`." "Wire format: $ATP."
expect_fail "section 3.3 naming the section but not the schema fails" \
    "$T" pointer "core.md:10"

T="$(new_tree item-5-no-schema)"
write_core "$T" "Specified in $ATP." "Wire format: $ATP; schema \`$SCHEMA\`."
expect_fail "item 5 naming the section but not the schema fails, even when a later section has it" \
    "$T" pointer "core.md:4"

T="$(new_tree wrapped)"
write_core "$T" "Specified in ATP-SPEC
   v1.0.0-rc1 §8.1, schema \`$SCHEMA\`." "Wire format: ATP-SPEC v1.0.0-rc1
§8.1; schema \`$SCHEMA\`."
expect_pass "a reference may wrap across a soft line break" "$T"

# --- authorization layer ----------------------------------------------------

T="$(new_tree authz-other-layer)"
write_core "$T" "Specified in $ATP, schema \`$SCHEMA\`." "Wire format: $ATP; schema \`$SCHEMA\`." \
    "Neither is permission: that is a broker policy decision under AAP." \
    "ARC is. ATX presents the credential. ARC enforces the policy."
expect_fail "a section 10 authorization bullet naming another layer fails, even when the next bullet names AAP" \
    "$T" pointer "core.md:29"

T="$(new_tree purpose-no-layer)"
write_core "$T" "Specified in $ATP, schema \`$SCHEMA\`." "Wire format: $ATP; schema \`$SCHEMA\`." \
    "Capability scope answers \"is this action permitted?\"."
expect_fail "section 1.5 not naming AAP fails, even when section 10 does" \
    "$T" pointer "core.md:22"

T="$(new_tree purpose-permitted)"
write_core "$T" "Specified in $ATP, schema \`$SCHEMA\`." "Wire format: $ATP; schema \`$SCHEMA\`." \
    "Neither is permission: that is a broker policy decision under AAP. An observer asks \"does this permitted action serve the declared objective?\"."
expect_fail "section 1.5 calling an action permitted in a sentence that does not name AAP fails, even when it names AAP elsewhere" \
    "$T" permission "core.md:22"

T="$(new_tree purpose-permitted-by-aap)"
write_core "$T" "Specified in $ATP, schema \`$SCHEMA\`." "Wire format: $ATP; schema \`$SCHEMA\`." \
    "Neither is permission: whether an action is permitted is a broker policy decision under AAP."
expect_pass "section 1.5 calling an action permitted in the sentence that names AAP passes" "$T"

T="$(new_tree readme-no-layer)"
write_core "$T" "Specified in $ATP, schema \`$SCHEMA\`." "Wire format: $ATP; schema \`$SCHEMA\`."
write_readme "$T" "They are not permission."
expect_fail "README use case 3 not naming AAP fails, even when the sections around it do" \
    "$T" pointer "README.md:9"

T="$(new_tree no-readme)"
write_core "$T" "Specified in $ATP, schema \`$SCHEMA\`." "Wire format: $ATP; schema \`$SCHEMA\`."
rm "$T/README.md"
expect_fail "a tree with no README.md fails instead of passing vacuously" \
    "$T" pointer "README.md"

# --- forge lab --------------------------------------------------------------

# lab_tree <name> <text> -> a passing tree whose README.md gains <text> as a
# paragraph on line 17, after the default README's 15 lines and a blank one.
lab_tree() {
    local t
    t="$(new_tree "$1")"
    write_core "$t" "Specified in $ATP, schema \`$SCHEMA\`." "Wire format: $ATP; schema \`$SCHEMA\`."
    printf '\n%s\n' "$2" >> "$t/README.md"
    printf '%s' "$t"
}

LAB='[forge lab](https://specs.opena2a.org/lab/forge)'

T="$(lab_tree lab-same-checks "Why you can check this yourself: the $LAB runs the same checks in a browser.")"
expect_fail "a sentence saying the forge lab runs the same checks fails" "$T" lab "README.md:17"

T="$(lab_tree lab-url-only "Or try to forge one in your browser at [specs.opena2a.org/lab/forge](https://specs.opena2a.org/lab/forge).")"
expect_fail "a sentence naming the lab only by its URL fails" "$T" lab "README.md:17"

T="$(lab_tree lab-name-only "What you can do today: the forge lab lets you present a credential past its lifetime.")"
expect_fail "a sentence naming the lab only by name fails" "$T" lab "README.md:17"

T="$(lab_tree lab-caveat-next-sentence "The $LAB runs the same checks in a browser. What it signs is not an ATX credential.")"
expect_fail "the caveat in the next sentence does not count" "$T" lab "README.md:17"

T="$(lab_tree lab-caveat "The $LAB signs a simplified object, not an ATX credential, so its verdicts are not conformance results.")"
expect_pass "a sentence naming the lab with the caveat passes" "$T"

T="$(lab_tree lab-caveat-wrapped "The $LAB signs a simplified object, not an
ATX credential.")"
expect_pass "the caveat may wrap across a soft line break" "$T"

T="$(lab_tree lab-wrapped-line "Conformance results come from the suite.
The $LAB runs the same checks in a browser.")"
expect_fail "a mention on a continuation line reports that line" "$T" lab "README.md:18"

T="$(lab_tree lab-other-file "No mention here.")"
mkdir -p "$T/docs"
printf '# Labs\n\nThe forge lab verifies credentials in a browser.\n' > "$T/docs/labs.md"
expect_fail "a mention in any other Markdown file fails" "$T" lab "docs/labs.md:3"

T="$(lab_tree lab-history "No mention here.")"
printf '# Changelog\n\nThe forge lab ran the same checks in a browser.\n' > "$T/CHANGELOG.md"
mkdir -p "$T/errata"
printf 'The forge lab ran the same checks in a browser.\n' > "$T/errata/ATX-E-0001.md"
expect_pass "CHANGELOG.md and errata/ record history and are not checked" "$T"

T="$(lab_tree lab-not-utf8 "No mention here.")"
printf 'The forge lab \377 runs the same checks.\n' > "$T/notes.md"
expect_fail "a Markdown file that is not UTF-8 fails" "$T" lab "notes.md"

# --- figure -----------------------------------------------------------------

ITEM5="Specified in $ATP, schema \`$SCHEMA\`."
S33="Wire format: $ATP; schema \`$SCHEMA\`."
PURPOSE="Neither is permission: that is a broker policy decision under AAP."
AUTHZ="AAP is the authorization layer. ATX presents the credential."

T="$(new_tree hma-stale-count)"
write_core "$T" "$ITEM5" "$S33" "$PURPOSE" "$AUTHZ" \
    "209 static plus 29 semantic plus 164 adversarial checks gate trust level; see the [HackMyAgent README]($HMA_README)."
expect_fail "a HackMyAgent row restating a check count fails, even beside the README link" \
    "$T" figure "core.md:36"

T="$(new_tree hma-current-count)"
write_core "$T" "$ITEM5" "$S33" "$PURPOSE" "$AUTHZ" \
    "Its 317 static checks gate trust level; see the [HackMyAgent README]($HMA_README)."
expect_fail "a HackMyAgent row restating the count its README states today still fails" \
    "$T" figure "core.md:36"

T="$(new_tree hma-no-link)"
write_core "$T" "$ITEM5" "$S33" "$PURPOSE" "$AUTHZ" \
    "Its checks gate trust level." "$AIM_ROW" \
    "Translates every CI build into a request; the [HackMyAgent README]($HMA_README) is linked in this row."
expect_fail "a HackMyAgent row without the README link fails, even when the next table row has it" \
    "$T" pointer "core.md:36"

T="$(new_tree aim-stale-count)"
write_core "$T" "$ITEM5" "$S33" "$PURPOSE" "$AUTHZ" "$HMA_ROW" \
    "8 factor trust feeds into ATX trust score, per [AIP §6.1]($AIP_SPEC)."
expect_fail "an AIM row restating a factor count fails, even beside the AIP §6.1 link" \
    "$T" figure "core.md:38"

T="$(new_tree aim-hyphenated-count)"
write_core "$T" "$ITEM5" "$S33" "$PURPOSE" "$AUTHZ" "$HMA_ROW" \
    "The 9-factor trust score of [AIP §6.1]($AIP_SPEC) feeds into ATX trust score."
expect_fail "an AIM row restating a hyphenated factor count fails" \
    "$T" figure "core.md:38"

T="$(new_tree aim-no-section)"
write_core "$T" "$ITEM5" "$S33" "$PURPOSE" "$AUTHZ" "$HMA_ROW" \
    "Its trust score, specified in [AIP]($AIP_SPEC), feeds into ATX trust score."
expect_fail "an AIM row linking AIP without naming §6.1 fails" \
    "$T" pointer "core.md:38"

T="$(new_tree aim-section-number)"
write_core "$T" "$ITEM5" "$S33" "$PURPOSE" "$AUTHZ" "$HMA_ROW" \
    "Its AIP §6.1 multi-factor trust score ([spec]($AIP_SPEC)) feeds into ATX trust score."
expect_pass "a section number ahead of multi-factor in the AIM row is not a count" "$T"

T="$(new_tree no-hma-row)"
write_core "$T" "$ITEM5" "$S33"
grep -v '^| HackMyAgent |' "$T/core.md" > "$T/core.tmp" && mv "$T/core.tmp" "$T/core.md"
expect_fail "a map with no HackMyAgent row fails instead of passing vacuously" \
    "$T" pointer "core.md"

# --- vacuous pass -----------------------------------------------------------

T="$(new_tree renamed)"
write_core "$T" "Specified in $ATP, schema \`$SCHEMA\`." "Wire format: $ATP; schema \`$SCHEMA\`."
sed 's/^### 3.3 Revocation flow$/### 3.3 Revoking/' "$T/core.md" > "$T/core.tmp" && mv "$T/core.tmp" "$T/core.md"
expect_fail "a renamed section heading fails instead of passing vacuously" \
    "$T" pointer "core.md"

T="$(new_tree empty)"
expect_fail "a tree with no core.md fails instead of passing vacuously" \
    "$T" pointer "core.md"

# --- summary ----------------------------------------------------------------

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d of %d test(s) failed\n' "$FAILED" "$COUNT"
    exit 1
fi
printf '# %d test(s) passed\n' "$COUNT"
