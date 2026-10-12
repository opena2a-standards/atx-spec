#!/usr/bin/env python3
"""Tests for the declaredPurpose category classes and the breadth measure.

core.md section 1.5.3 gives each core category a breadth class and a
sensitivity class, and section 1.5.4 computes a declaration's breadth from its
capabilityJustification. The classes are published twice, as the section 1.5.3
table and as schemas/purpose-category-classes-v1.json, and the measure is pinned
by schemas/purpose-breadth-vectors-v1.json. These tests assert that:

  - the registry file, the section 1.5.3 table and the schema's category enum
    list the same 15 categories in the same order, with the same classes;
  - every class value is one the registry declares, the custom default is the
    broadest and most sensitive class, and the two dual-use categories are not
    narrow (section 1.5.3);
  - each vector's declaredPurpose is valid under the schema, and the breadth
    section 1.5.4 computes for it is the one the vector pins.

    python3 scripts/test_purpose_classes.py

Needs python3 and the 'jsonschema' package, as scripts/validate_examples.py
does. Output is TAP-ish: one line per leaf test. Exit 0 when every test passes.
"""

import copy
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from validate_examples import Draft202012Validator, extract_block  # noqa: E402


def load(relative):
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


SCHEMA = load("schemas/atx-credential-v1.1.schema.json")
REGISTRY = load("schemas/purpose-category-classes-v1.json")
VECTORS = load("schemas/purpose-breadth-vectors-v1.json")
EXAMPLE = json.loads(extract_block(ROOT / "core.md", "### 1.1 ATX schema"))
VALIDATOR = Draft202012Validator(SCHEMA)

BREADTH = [c["class"] for c in REGISTRY["breadthClasses"]]
SENSITIVITY = REGISTRY["sensitivityClasses"]
ROW = re.compile(r"^\| `([^`]+)` \| `([^`]+)` \| `([^`]+)` \|$")


def section(heading, next_heading):
    lines = (ROOT / "core.md").read_text(encoding="utf-8").splitlines()
    start = lines.index(heading)
    end = lines.index(next_heading, start)
    return lines[start + 1:end]


def namespace(capability):
    # Everything before the colon, an organization's domain prefix included.
    return capability.partition(":")[0]


def breadth(purpose):
    """The section 1.5.4 measure, read from the registry file."""
    namespaces = sorted({namespace(c) for c in purpose["capabilityJustification"]})
    computed = next(
        c["class"] for c in REGISTRY["breadthClasses"]
        if c["maxNamespaces"] is None or len(namespaces) <= c["maxNamespaces"]
    )
    rows = {r["category"]: r for r in REGISTRY["categories"]}
    category_class = rows.get(purpose["category"], REGISTRY["customCategory"])["breadthClass"]
    return {
        "namespaces": namespaces,
        "namespaceCount": len(namespaces),
        "computedBreadthClass": computed,
        "categoryBreadthClass": category_class,
        "effectiveBreadthClass": max(computed, category_class, key=BREADTH.index),
    }


def registry_rows():
    return [(r["category"], r["breadthClass"], r["sensitivityClass"])
            for r in REGISTRY["categories"]]


def test_registry_matches_schema_enum():
    enum = SCHEMA["$defs"]["declaredPurpose"]["properties"]["category"]["anyOf"][0]["enum"]
    names = [r[0] for r in registry_rows()]
    if names != enum:
        return f"registry lists {names}, schema enum lists {enum}"
    return None


def test_core_table_matches_registry():
    table = [ROW.match(l).groups() for l in section("#### 1.5.3 Vocabulary",
                                                     "#### 1.5.4 Breadth is measured, not claimed")
             if ROW.match(l)]
    if table != registry_rows():
        return f"core.md section 1.5.3 table rows {table} differ from the registry"
    return None


def test_classes_are_declared():
    bad = [r for r in registry_rows() if r[1] not in BREADTH or r[2] not in SENSITIVITY]
    custom = REGISTRY["customCategory"]
    if custom["breadthClass"] not in BREADTH or custom["sensitivityClass"] not in SENSITIVITY:
        bad.append(("customCategory", custom["breadthClass"], custom["sensitivityClass"]))
    return f"undeclared class values: {bad}" if bad else None


def test_breadth_bounds_increase():
    bounds = [c["maxNamespaces"] for c in REGISTRY["breadthClasses"]]
    finite = bounds[:-1]
    if bounds[-1] is not None:
        return f"the broadest class is bounded at {bounds[-1]}"
    if any(not isinstance(b, int) or b < 0 for b in finite) or finite != sorted(set(finite)):
        return f"bounds {finite} are not strictly increasing non-negative integers"
    return None


def test_custom_default_is_broadest_and_most_sensitive():
    custom = REGISTRY["customCategory"]
    if (custom["breadthClass"], custom["sensitivityClass"]) != (BREADTH[-1], SENSITIVITY[-1]):
        return f"custom default is {custom}, not ({BREADTH[-1]}, {SENSITIVITY[-1]})"
    return None


def test_dual_use_categories_are_not_narrow():
    rows = {r[0]: r[1] for r in registry_rows()}
    narrow = [c for c in ("security-operations", "device-control") if rows.get(c) == BREADTH[0]]
    return f"declared {BREADTH[0]}: {narrow}" if narrow else None


def test_first_vector_is_the_section_1_1_example():
    if VECTORS["vectors"][0]["declaredPurpose"] != EXAMPLE["declaredPurpose"]:
        return "the first vector's declaredPurpose differs from the section 1.1 example"
    return None


def test_vectors_pin_each_floor_outcome():
    outcomes = set()
    for v in VECTORS["vectors"]:
        e = v["expected"]
        rank = BREADTH.index
        outcomes.add("raised" if rank(e["computedBreadthClass"]) > rank(e["categoryBreadthClass"])
                     else "kept" if e["computedBreadthClass"] == e["categoryBreadthClass"]
                     else "not lowered")
    missing = {"raised", "kept", "not lowered"} - outcomes
    return f"no vector pins a floor that is {sorted(missing)}" if missing else None


def vector_valid(vector):
    def run():
        credential = copy.deepcopy(EXAMPLE)
        credential["declaredPurpose"] = vector["declaredPurpose"]
        credential["capabilities"] = list(vector["declaredPurpose"]["capabilityJustification"])
        errors = list(VALIDATOR.iter_errors(credential))
        return "; ".join(f"{e.json_path}: {e.message}" for e in errors[:3]) or None
    return run


def vector_breadth(vector):
    def run():
        got = breadth(vector["declaredPurpose"])
        return None if got == vector["expected"] else f"computed {got}, pinned {vector['expected']}"
    return run


CASES = [
    ("the registry lists the schema's 15 core categories in order", test_registry_matches_schema_enum),
    ("the core.md section 1.5.3 table matches the registry row for row",
     test_core_table_matches_registry),
    ("every class value is one the registry declares", test_classes_are_declared),
    ("breadth class bounds increase and the broadest is unbounded", test_breadth_bounds_increase),
    ("a custom category defaults to the broadest, most sensitive class",
     test_custom_default_is_broadest_and_most_sensitive),
    ("security-operations and device-control are not narrow (section 1.5.3)",
     test_dual_use_categories_are_not_narrow),
    ("the first vector is the section 1.1 example's declaredPurpose",
     test_first_vector_is_the_section_1_1_example),
    ("the vectors pin a raised, a kept and a not-lowered floor", test_vectors_pin_each_floor_outcome),
]
for _v in VECTORS["vectors"]:
    CASES.append((f"vector {_v['name']}: declaredPurpose is valid under the schema", vector_valid(_v)))
    CASES.append((f"vector {_v['name']}: computed breadth matches the pinned one", vector_breadth(_v)))


def main() -> int:
    failed = 0
    for count, (name, case) in enumerate(CASES, start=1):
        reason = case()
        if reason is None:
            print(f"ok {count} - {name}")
            continue
        failed += 1
        print(f"not ok {count} - {name}")
        print(f"  ---\n  reason: {reason}\n  ---")
    print(f"1..{len(CASES)}")
    if failed:
        print(f"# {failed} of {len(CASES)} failed")
        return 1
    print(f"# all {len(CASES)} passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
