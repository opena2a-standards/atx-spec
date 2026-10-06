#!/usr/bin/env bash
# Tests for the errata object: scripts/gen_errata_index.py, scripts/check_errata.py,
# core.md's header line and the conformance-counts workflow wiring.
#
# Every failing shape the validator is supposed to catch is built here in a
# scratch copy of the tree and asserted to exit 1 naming the erratum and the
# rule; the delivered tree itself is asserted to exit 0. Shell rather than pytest
# so the same CI step that runs the validator can run these with nothing
# installed: the runner has bash and python3 and that is all this needs.
#
#   bash scripts/test_errata.sh
#
# Output is TAP-ish: one line per leaf test, each named with the criterion it
# covers as its first token. Exit 0 when every test passes.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$REPO/.github/workflows/conformance-counts.yml"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

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

assert() {  # assert <leaf test name> <condition-exit-code> <why>
    if [ "$2" -eq 0 ]; then ok "$1"; else not_ok "$1" "$3"; fi
}

# --- fixtures ---------------------------------------------------------------

SUITE="$TMP/suite"
mkdir -p "$SUITE/fixtures"
: > "$SUITE/fixtures/atx-e-example.json"
: > "$SUITE/fixtures/atx-e-second.json"

new_tree() {  # new_tree <name> -> path to a scratch copy of the tree under test
    local dest="$TMP/$1"
    mkdir -p "$dest"
    cp "$REPO/core.md" "$REPO/CHANGELOG.md" "$dest/"
    cp -r "$REPO/errata" "$dest/errata"
    printf '%s' "$dest"
}

erratum() {  # erratum <root> <file> <id> <status> <class> <fixtures> <accepted>
    cat > "$1/errata/$2" <<EOF
---
id: $3
status: $4
class: $5
affectsDocument: core.md
affectsWire: false
sections:
  - "§7.2"
oldText: |
  The published sentence, verbatim.
newText: |
  The corrected sentence, verbatim.
fixtures: $6
filed: "2026-09-01"
accepted: $7
---

# $3: a scratch erratum built by scripts/test_errata.sh

## What the text says

Scratch body text.
EOF
}

regen() {  # regen <root>: rebuild the scratch index so index-stale does not mask
    python3 "$REPO/scripts/gen_errata_index.py" --errata-dir "$1/errata" > /dev/null 2>&1
}

set_header() {  # set_header <root> <ATX-E-NNNN|none>
    python3 - "$1/core.md" "$2" <<'PY'
import pathlib, re, sys
path, value = pathlib.Path(sys.argv[1]), sys.argv[2]
text = path.read_text(encoding="utf-8")
path.write_text(
    re.sub(
        r"^\*\*Errata:\*\*.*$",
        f"**Errata:** errata/README.md, incorporated through {value}",
        text,
        count=1,
        flags=re.M,
    ),
    encoding="utf-8",
)
PY
}

changelog_note() {  # changelog_note <root> <id>
    printf '\n- %s recorded for the scratch tree.\n' "$2" >> "$1/CHANGELOG.md"
}

run_check() {  # run_check <root> [extra args...] -> exit code, output in $OUT
    local root="$1"
    shift
    OUT="$TMP/out.txt"
    python3 "$REPO/scripts/check_errata.py" --root "$root" --suite "$SUITE" "$@" \
        > "$OUT" 2>&1
    return $?
}

expect_fail() {  # expect_fail <leaf name> <root> <rule> <named-file>
    local name="$1" root="$2" rule="$3" named="$4" rc
    run_check "$root"
    rc=$?
    if [ "$rc" -ne 1 ]; then
        not_ok "$name" "expected exit 1, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
        return
    fi
    if ! grep -q -- "\[$rule\]" "$OUT"; then
        not_ok "$name" "exit 1 but rule [$rule] not named: $(head -c 400 "$OUT" | tr '\n' ' ')"
        return
    fi
    if [ -n "$named" ] && ! grep -q -- "$named" "$OUT"; then
        not_ok "$name" "rule named but $named not named: $(head -c 400 "$OUT" | tr '\n' ' ')"
        return
    fi
    ok "$name"
}

expect_pass() {  # expect_pass <leaf name> <root>
    local name="$1" root="$2" rc
    run_check "$root"
    rc=$?
    assert "$name" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)" \
        "expected exit 0, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
}

# --- ATXS-01.AC1: the erratum file, the generated index, the header line ------

T="$(new_tree ac1-idempotent)"
erratum "$T" ATX-E-0001.md ATX-E-0001 proposed clarification '[]' ''
erratum "$T" ATX-E-0002.md ATX-E-0002 accepted security '["atx-e-example.json"]' '"2026-09-02"'
regen "$T"
cp "$T/errata/README.md" "$TMP/first-run.md"
regen "$T"
cmp -s "$TMP/first-run.md" "$T/errata/README.md"
assert "ATXS-01.AC1 running gen_errata_index.py twice yields a byte-identical errata/README.md" \
    $? "second run differs from the first"

grep -q 'ATX-E-0001' "$T/errata/README.md" && grep -q 'ATX-E-0002' "$T/errata/README.md"
assert "ATXS-01.AC1 the generated index lists every errata/ATX-E-NNNN.md file" \
    $? "an erratum file is missing from the generated index"

python3 "$REPO/scripts/gen_errata_index.py" --errata-dir "$REPO/errata" --check > /dev/null 2>&1
assert "ATXS-01.AC1 the committed errata/README.md is what the generator produces" \
    $? "errata/README.md is stale; run python3 scripts/gen_errata_index.py"

T="$(new_tree ac1-stale-index)"
erratum "$T" ATX-E-0001.md ATX-E-0001 proposed editorial '[]' ''
regen "$T"
printf '\nHand-written line the generator would never emit.\n' >> "$T/errata/README.md"
expect_fail "ATXS-01.AC1 a committed README.md that differs from the generator output fails check_errata.py" \
    "$T" index-stale "errata/README.md"

T="$(new_tree ac1-header-stale)"
erratum "$T" ATX-E-0003.md ATX-E-0003 incorporated editorial '[]' '"2026-09-02"'
changelog_note "$T" ATX-E-0003
regen "$T"
expect_fail "ATXS-01.AC1 a header line not naming the highest incorporated erratum fails check_errata.py" \
    "$T" header-errata-line "core.md"

T="$(new_tree ac1-header-current)"
erratum "$T" ATX-E-0003.md ATX-E-0003 incorporated editorial '[]' '"2026-09-02"'
changelog_note "$T" ATX-E-0003
regen "$T"
set_header "$T" ATX-E-0003
expect_pass "ATXS-01.AC1 a header naming the highest incorporated erratum passes check_errata.py" "$T"

T="$(new_tree ac1-header-missing)"
python3 - "$T/core.md" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
p.write_text(re.sub(r"^\*\*Errata:\*\*.*\n", "", p.read_text(encoding="utf-8"), flags=re.M), encoding="utf-8")
PY
expect_fail "ATXS-01.AC1 a core.md with no Errata header line fails check_errata.py" \
    "$T" header-errata-line "core.md"

grep -c '^\*\*Errata:\*\* errata/README\.md, incorporated through \(ATX-E-[0-9]\{4\}\|none\)$' \
    "$REPO/core.md" | grep -qx 1
assert "ATXS-01.AC1 core.md carries exactly one well-formed Errata header line" \
    $? "core.md does not carry exactly one **Errata:** errata/README.md, incorporated through <id|none> line"

python3 - "$REPO/core.md" <<'PY'
import pathlib, sys
lines = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").split("\n")
block = [i for i, l in enumerate(lines) if l.startswith("**Document version:**")]
assert block, "no **Document version:** line"
start = block[0]
end = start
while end + 1 < len(lines) and lines[end + 1].startswith("**"):
    end += 1
assert any(lines[i].startswith("**Errata:**") for i in range(start, end + 1)), \
    "the Errata line is not inside the header block"
PY
assert "ATXS-01.AC1 the Errata line sits inside core.md's header block" \
    $? "the **Errata:** line is outside the **Document version:** header block"

# "core.md gains one line and nothing else" is a statement about the commit that
# introduces the errata object, not about the current text: core.md is allowed to
# change again afterwards. So the commit is found in history, as the earliest one
# that adds the **Errata:** line, and its own change to core.md is asserted. A
# checkout without that history (a shallow CI clone, an exported tarball) skips.
DIFF_NAME="ATXS-01.AC1 the commit that adds the Errata line changes core.md by that one line and nothing else"
ADD_SHA=$(git -C "$REPO" log --reverse --format=%H -S'**Errata:**' -- core.md 2>/dev/null | head -n 1)
if [ "$(git -C "$REPO" rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
    skip "$DIFF_NAME" "this checkout is a shallow clone, whose history may not reach the commit that adds the Errata line"
elif [ -z "$ADD_SHA" ]; then
    skip "$DIFF_NAME" "no commit in this checkout's history adds the Errata line to core.md"
elif ! git -C "$REPO" rev-parse --verify --quiet "$ADD_SHA^1^{commit}" > /dev/null 2>&1; then
    skip "$DIFF_NAME" "${ADD_SHA:0:7}, the commit that adds the Errata line, has no parent to compare against"
else
    DIFF="$TMP/core-diff.txt"
    git -C "$REPO" diff "$ADD_SHA^1" "$ADD_SHA" -- core.md > "$DIFF" 2>/dev/null
    ADDED=$(grep -c '^+[^+]' "$DIFF")
    REMOVED=$(grep -c '^-[^-]' "$DIFF")
    if [ "$ADDED" -eq 1 ] && [ "$REMOVED" -eq 0 ] && grep -q '^+\*\*Errata:\*\*' "$DIFF"; then
        ok "$DIFF_NAME"
    else
        not_ok "$DIFF_NAME" "$ADDED added line(s), $REMOVED removed line(s)"
    fi
fi

python3 -B - "$REPO" <<'PY'
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(sys.argv[1]) / "scripts"))
from gen_errata_index import FRONTMATTER_KEYS, parse_frontmatter
text = (pathlib.Path(sys.argv[1]) / "errata" / "TEMPLATE.md").read_text(encoding="utf-8")
data, _ = parse_frontmatter(text)
assert set(data) == set(FRONTMATTER_KEYS), sorted(data)
assert data["affectsWire"] is False, data["affectsWire"]
assert isinstance(data["sections"], list) and isinstance(data["fixtures"], list)
assert data["oldText"].endswith("\n") and data["newText"].endswith("\n")
assert data["accepted"] == "", repr(data["accepted"])
PY
assert "ATXS-01.AC1 the erratum template carries exactly the eleven frontmatter keys with their types" \
    $? "errata/TEMPLATE.md frontmatter does not match the key contract"

python3 -B - "$REPO" <<'PY'
# The restricted parser and PyYAML must agree: an erratum is real YAML.
import datetime, pathlib, sys
try:
    import yaml
except ImportError:
    sys.exit(7)
sys.path.insert(0, str(pathlib.Path(sys.argv[1]) / "scripts"))
from gen_errata_index import parse_frontmatter
text = (pathlib.Path(sys.argv[1]) / "errata" / "TEMPLATE.md").read_text(encoding="utf-8")
mine, _ = parse_frontmatter(text)
block = text.split("---\n")[1]
theirs = yaml.safe_load(block)


def norm(v):
    if v is None:
        return ""
    if isinstance(v, (datetime.date, datetime.datetime)):
        return v.isoformat()
    if isinstance(v, list):
        return [norm(i) for i in v]
    return v


assert {k: norm(v) for k, v in theirs.items()} == {k: norm(v) for k, v in mine.items()}, (
    theirs,
    mine,
)
PY
rc=$?
if [ "$rc" -eq 7 ]; then
    skip "ATXS-01.AC1 the erratum frontmatter parses identically under PyYAML" "PyYAML is not installed"
else
    assert "ATXS-01.AC1 the erratum frontmatter parses identically under PyYAML" \
        "$rc" "the restricted parser and yaml.safe_load disagree"
fi

# --- ATXS-01.AC2: the failing shapes ----------------------------------------

expect_pass "ATXS-01.AC2 the delivered tree, whose errata directory holds no erratum, exits 0" "$REPO"

T="$(new_tree ac2-proposed-no-fixture)"
erratum "$T" ATX-E-0001.md ATX-E-0001 proposed security '[]' ''
regen "$T"
expect_pass "ATXS-01.AC2 a proposed erratum of any class with no fixture exits 0" "$T"

T="$(new_tree ac2-accepted-ok)"
erratum "$T" ATX-E-0001.md ATX-E-0001 accepted security '["atx-e-example.json"]' '"2026-09-02"'
changelog_note "$T" ATX-E-0001
regen "$T"
expect_pass "ATXS-01.AC2 an accepted security erratum naming an existing fixture and listed in CHANGELOG exits 0" "$T"

T="$(new_tree ac2-fixture-required)"
erratum "$T" ATX-E-0001.md ATX-E-0001 accepted security '[]' '"2026-09-02"'
changelog_note "$T" ATX-E-0001
regen "$T"
expect_fail "ATXS-01.AC2 an accepted non-editorial erratum naming no fixture exits 1 naming fixture-required" \
    "$T" fixture-required "ATX-E-0001.md"

T="$(new_tree ac2-fixture-required-incorporated)"
erratum "$T" ATX-E-0001.md ATX-E-0001 incorporated clarification '[]' '"2026-09-02"'
changelog_note "$T" ATX-E-0001
regen "$T"
set_header "$T" ATX-E-0001
expect_fail "ATXS-01.AC2 an incorporated non-editorial erratum naming no fixture exits 1 naming fixture-required" \
    "$T" fixture-required "ATX-E-0001.md"

T="$(new_tree ac2-fixture-missing)"
erratum "$T" ATX-E-0001.md ATX-E-0001 accepted clarification '["atx-e-not-in-suite.json"]' '"2026-09-02"'
changelog_note "$T" ATX-E-0001
regen "$T"
expect_fail "ATXS-01.AC2 an accepted erratum naming a fixture absent from the suite exits 1 naming fixture-missing" \
    "$T" fixture-missing "ATX-E-0001.md"

T="$(new_tree ac2-changelog-missing)"
erratum "$T" ATX-E-0001.md ATX-E-0001 accepted clarification '["atx-e-example.json"]' '"2026-09-02"'
regen "$T"
expect_fail "ATXS-01.AC2 an accepted erratum absent from CHANGELOG.md exits 1 naming changelog-missing" \
    "$T" changelog-missing "ATX-E-0001.md"

T="$(new_tree ac2-editorial-accepted-no-fixture)"
erratum "$T" ATX-E-0001.md ATX-E-0001 accepted editorial '[]' '"2026-09-02"'
changelog_note "$T" ATX-E-0001
regen "$T"
expect_pass "ATXS-01.AC2 an accepted editorial erratum with no fixture exits 0" "$T"

T="$(new_tree ac2-unknown-key)"
erratum "$T" ATX-E-0001.md ATX-E-0001 proposed editorial '[]' ''
printf 'severity: high\n' > "$TMP/extra"
python3 - "$T/errata/ATX-E-0001.md" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text(encoding="utf-8").replace("filed:", "severity: high\nfiled:", 1), encoding="utf-8")
PY
regen "$T"
expect_fail "ATXS-01.AC2 an unknown frontmatter key exits 1 naming unknown-key" \
    "$T" unknown-key "ATX-E-0001.md"

T="$(new_tree ac2-missing-key)"
erratum "$T" ATX-E-0001.md ATX-E-0001 proposed editorial '[]' ''
python3 - "$T/errata/ATX-E-0001.md" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
p.write_text(re.sub(r"^affectsWire:.*\n", "", p.read_text(encoding="utf-8"), flags=re.M), encoding="utf-8")
PY
regen "$T"
expect_fail "ATXS-01.AC2 a missing frontmatter key exits 1 naming missing-key" \
    "$T" missing-key "ATX-E-0001.md"

T="$(new_tree ac2-bad-status)"
erratum "$T" ATX-E-0001.md ATX-E-0001 withdrawn editorial '[]' ''
regen "$T"
expect_fail "ATXS-01.AC2 an unknown status exits 1 naming bad-status" \
    "$T" bad-status "ATX-E-0001.md"

T="$(new_tree ac2-bad-class)"
erratum "$T" ATX-E-0001.md ATX-E-0001 proposed typo '[]' ''
regen "$T"
expect_fail "ATXS-01.AC2 an unknown class exits 1 naming bad-class" \
    "$T" bad-class "ATX-E-0001.md"

T="$(new_tree ac2-id-mismatch)"
erratum "$T" ATX-E-0001.md ATX-E-0009 proposed editorial '[]' ''
regen "$T"
expect_fail "ATXS-01.AC2 an id that is not the filename stem exits 1 naming id-filename-mismatch" \
    "$T" id-filename-mismatch "ATX-E-0001.md"

T="$(new_tree ac2-id-format)"
erratum "$T" ATX-E-0001.md ATX-E-1 proposed editorial '[]' ''
regen "$T"
expect_fail "ATXS-01.AC2 an id that does not match ATX-E-NNNN exits 1 naming id-format" \
    "$T" id-format "ATX-E-0001.md"

T="$(new_tree ac2-duplicate-id)"
erratum "$T" ATX-E-0001.md ATX-E-0001 proposed editorial '[]' ''
erratum "$T" ATX-E-0002.md ATX-E-0001 proposed editorial '[]' ''
regen "$T"
expect_fail "ATXS-01.AC2 two erratum files sharing an id exit 1 naming duplicate-id" \
    "$T" duplicate-id "ATX-E-0002.md"

T="$(new_tree ac2-security-proposed)"
erratum "$T" ATX-E-0004.md ATX-E-0004 proposed security '[]' ''
regen "$T"
set_header "$T" ATX-E-0004
expect_fail "ATXS-01.AC2 a proposed security erratum in a tree whose header names it incorporated exits 1 naming security-proposed-incorporated" \
    "$T" security-proposed-incorporated "ATX-E-0004.md"

T="$(new_tree ac2-accepted-date)"
erratum "$T" ATX-E-0001.md ATX-E-0001 proposed editorial '[]' '"2026-09-02"'
regen "$T"
expect_fail "ATXS-01.AC2 a proposed erratum carrying an accepted date exits 1 naming accepted-date" \
    "$T" accepted-date "ATX-E-0001.md"

T="$(new_tree ac2-accepted-date-missing)"
erratum "$T" ATX-E-0001.md ATX-E-0001 accepted editorial '[]' ''
changelog_note "$T" ATX-E-0001
regen "$T"
expect_fail "ATXS-01.AC2 an accepted erratum with an empty accepted date exits 1 naming accepted-date" \
    "$T" accepted-date "ATX-E-0001.md"

T="$(new_tree ac2-bad-type)"
erratum "$T" ATX-E-0001.md ATX-E-0001 proposed editorial '[]' ''
python3 - "$T/errata/ATX-E-0001.md" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text(encoding="utf-8").replace("affectsWire: false", "affectsWire: maybe"), encoding="utf-8")
PY
regen "$T"
expect_fail "ATXS-01.AC2 a non-boolean affectsWire exits 1 naming bad-type" \
    "$T" bad-type "ATX-E-0001.md"

T="$(new_tree ac2-frontmatter-missing)"
printf '# ATX-E-0001: no frontmatter at all\n\nBody.\n' > "$T/errata/ATX-E-0001.md"
expect_fail "ATXS-01.AC2 an erratum file with no frontmatter block exits 1 naming frontmatter-missing" \
    "$T" frontmatter-missing "ATX-E-0001.md"

# --- ATXS-01.AC3: the workflow wiring and the public text rule ---------------

grep -q 'python3 scripts/check_conformance_counts.py --suite .suite' "$WORKFLOW"
assert "ATXS-01.AC3 conformance-counts.yml still runs check_conformance_counts.py --suite .suite" \
    $? "the existing conformance-counts step is gone"

grep -q 'python3 scripts/check_errata.py --suite .suite' "$WORKFLOW"
assert "ATXS-01.AC3 conformance-counts.yml runs check_errata.py --suite .suite" \
    $? "the workflow does not run scripts/check_errata.py --suite .suite"

COUNTS_LINE=$(grep -n 'python3 scripts/check_conformance_counts.py --suite .suite' "$WORKFLOW" | head -1 | cut -d: -f1)
ERRATA_LINE=$(grep -n 'python3 scripts/check_errata.py --suite .suite' "$WORKFLOW" | head -1 | cut -d: -f1)
[ -n "$COUNTS_LINE" ] && [ -n "$ERRATA_LINE" ] && [ "$ERRATA_LINE" -gt "$COUNTS_LINE" ]
assert "ATXS-01.AC3 the errata step runs after the conformance-counts step in the workflow text" \
    $? "check_errata.py does not run after check_conformance_counts.py"

python3 - "$WORKFLOW" <<'PY'
# One job, so "after it" and "in the same job" are the same statement, and the
# errata step carries no continue-on-error and no if:.
import pathlib, re, sys
lines = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").split("\n")
jobs = [i for i, l in enumerate(lines) if l == "jobs:"]
assert len(jobs) == 1, "expected exactly one jobs: block"
job_keys = [l for l in lines[jobs[0] + 1:] if re.match(r"^  [A-Za-z0-9_-]+:\s*$", l)]
assert len(job_keys) == 1, f"expected one job, found {job_keys}"
start = next(i for i, l in enumerate(lines) if "python3 scripts/check_errata.py --suite .suite" in l)
top = start
while top > 0 and not lines[top].lstrip().startswith("- "):
    top -= 1
end = start + 1
while end < len(lines) and not lines[end].lstrip().startswith("- "):
    end += 1
step = "\n".join(lines[top:end])
assert "continue-on-error" not in step, "errata step carries continue-on-error"
assert not re.search(r"^\s+if:", step, flags=re.M), "errata step carries an if:"
PY
assert "ATXS-01.AC3 the errata step is in the single conformance-counts job with no continue-on-error and no if:" \
    $? "the errata step is guarded, or the workflow has more than one job"

python3 - "$WORKFLOW" <<'PY'
import sys
try:
    import yaml
except ImportError:
    sys.exit(7)
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
job = list(doc["jobs"].values())[0]
runs = [s.get("run", "") for s in job["steps"]]
counts = [i for i, r in enumerate(runs) if "check_conformance_counts.py --suite .suite" in r]
errata = [i for i, r in enumerate(runs) if "check_errata.py --suite .suite" in r]
assert counts and errata and errata[0] > counts[0], (counts, errata)
step = job["steps"][errata[0]]
assert "continue-on-error" not in step and "if" not in step, step
PY
rc=$?
if [ "$rc" -eq 7 ]; then
    skip "ATXS-01.AC3 conformance-counts.yml parses as YAML with the errata step after the counts step" \
        "PyYAML is not installed"
else
    assert "ATXS-01.AC3 conformance-counts.yml parses as YAML with the errata step after the counts step" \
        "$rc" "the workflow does not parse as YAML, or the parsed step order is wrong"
fi

MISSING=0
while IFS= read -r banned; do
    grep -q -F -- "$banned" "$REPO/scripts/check_errata.py" || MISSING=1
done <<'EOF'
@opena2a/atx-verify
atx-conformance Go
atx-conformance Python
AIM Java
Registry Go
EOF
assert "ATXS-01.AC3 check_errata.py commits the five implementation names it bans" \
    "$MISSING" "a roster name from the ruling is not in BANNED_STRINGS"

FOUND=0
while IFS= read -r banned; do
    if grep -r -q -i -F -- "$banned" "$REPO/errata"; then FOUND=1; fi
done <<'EOF'
@opena2a/atx-verify
atx-conformance Go
atx-conformance Python
AIM Java
Registry Go
EOF
assert "ATXS-01.AC3 no implementation name occurs anywhere under errata/" \
    "$FOUND" "a banned implementation name appears under errata/"

T="$(new_tree ac3-implementation-name)"
erratum "$T" ATX-E-0001.md ATX-E-0001 proposed editorial '[]' ''
printf '\nVerified against AIM Java before filing.\n' >> "$T/errata/ATX-E-0001.md"
regen "$T"
expect_fail "ATXS-01.AC3 an erratum naming an implementation exits 1 naming implementation-name" \
    "$T" implementation-name "ATX-E-0001.md"

T="$(new_tree ac3-implementation-name-index)"
printf '\nThe suite is atx-conformance Go.\n' >> "$T/errata/README.md"
expect_fail "ATXS-01.AC3 an index naming an implementation exits 1 naming implementation-name" \
    "$T" implementation-name "errata/README.md"

# --- summary ----------------------------------------------------------------

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d of %d test(s) failed, %d skipped\n' "$FAILED" "$COUNT" "$SKIPPED"
    exit 1
fi
printf '# %d test(s) passed, %d skipped\n' "$((COUNT - SKIPPED))" "$SKIPPED"
