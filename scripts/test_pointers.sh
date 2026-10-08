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
# Sections 1.5 and 10 follow section 4 so the line numbers above them stay put;
# the check finds a section by its opening line, wherever it sits. A tree with
# no README.md also gets the default one from write_readme.
write_core() {
    local purpose="${4-Neither is permission: that is a broker policy decision under AAP.}"
    local authz="${5-AAP is the authorization layer. ATX presents the credential.}"
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
