#!/usr/bin/env python3
"""Validate the spec's inline JSON examples against the repo's JSON Schemas.

Reads schemas/examples-map.json, a list of entries:
    { "file": "core.md",
      "heading": "### 1.1 ATX schema",
      "schema": "schemas/atx-credential-v1.1.schema.json" }

For each entry: find the heading line in the file, take the first fenced
```json block after it, parse it, and validate it against the schema.
Also metaschema-checks every schemas/*.schema.json.

An entry may also carry "mustReject": a list of { "name", "patch" } variants.
Each patch is a JSON Patch (RFC 6902) limited to the "test" and "remove"
operations, applied to a copy of the example; the schema must refuse the
result. A "test" that does not hold fails the run, so a variant cannot go on
passing after the example it edits has changed under it.

Formats (date-time, uuid) are treated as annotations, not assertions, matching
library defaults across implementations; structural keywords (type, enum,
pattern, required) carry the contract.

Exit code 0 = all schemas well-formed, all mapped examples valid and every
mustReject variant refused.
"""

import copy
import json
import pathlib
import sys

try:
    from jsonschema import Draft202012Validator
except ImportError:
    print("error: the 'jsonschema' package is required (pip install jsonschema)")
    sys.exit(2)

ROOT = pathlib.Path(__file__).resolve().parent.parent


def extract_block(md_path: pathlib.Path, heading: str) -> str:
    lines = md_path.read_text(encoding="utf-8").splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == heading)
    except StopIteration:
        raise SystemExit(f"error: heading {heading!r} not found in {md_path}")
    in_block = False
    block: list[str] = []
    for line in lines[start + 1:]:
        if not in_block and line.strip() == "```json":
            in_block = True
            continue
        if in_block:
            if line.strip() == "```":
                return "\n".join(block)
            block.append(line)
        elif line.startswith("#") and not block:
            raise SystemExit(
                f"error: no ```json block between {heading!r} and the next heading in {md_path}"
            )
    raise SystemExit(f"error: unterminated ```json block after {heading!r} in {md_path}")


class PatchError(Exception):
    pass


def _key(node, token: str, pointer: str):
    if isinstance(node, list):
        if not token.isdigit() or int(token) >= len(node):
            raise PatchError(f"{pointer}: no array index {token!r}")
        return int(token)
    if isinstance(node, dict):
        if token not in node:
            raise PatchError(f"{pointer}: no member {token!r}")
        return token
    raise PatchError(f"{pointer}: cannot step into a {type(node).__name__}")


def apply_patch(doc, ops):
    """Apply a JSON Patch (RFC 6902) of `test` and `remove` operations to a copy of doc."""
    doc = copy.deepcopy(doc)
    for op in ops:
        pointer = op.get("path", "")
        if not pointer.startswith("/"):
            raise PatchError(f"path {pointer!r} does not point below the document root")
        tokens = [t.replace("~1", "/").replace("~0", "~") for t in pointer[1:].split("/")]
        parent = doc
        for token in tokens[:-1]:
            parent = parent[_key(parent, token, pointer)]
        key = _key(parent, tokens[-1], pointer)
        if op.get("op") == "test":
            if parent[key] != op.get("value"):
                raise PatchError(
                    f"test failed at {pointer}: found {parent[key]!r}, expected {op.get('value')!r}"
                )
        elif op.get("op") == "remove":
            del parent[key]
        else:
            raise PatchError(f"unsupported op {op.get('op')!r} (only test and remove)")
    return doc


def main() -> int:
    failures = 0

    schema_files = sorted((ROOT / "schemas").glob("*.schema.json"))
    if not schema_files:
        print("error: no schemas/*.schema.json found")
        return 1
    for sf in schema_files:
        schema = json.loads(sf.read_text(encoding="utf-8"))
        try:
            Draft202012Validator.check_schema(schema)
            print(f"schema OK      {sf.relative_to(ROOT)}")
        except Exception as exc:  # noqa: BLE001 - report and fail
            print(f"schema INVALID {sf.relative_to(ROOT)}: {exc}")
            failures += 1

    map_path = ROOT / "schemas" / "examples-map.json"
    entries = json.loads(map_path.read_text(encoding="utf-8")) if map_path.exists() else []
    for entry in entries:
        md = ROOT / entry["file"]
        schema_path = ROOT / entry["schema"]
        raw = extract_block(md, entry["heading"])
        try:
            instance = json.loads(raw)
        except json.JSONDecodeError as exc:
            print(f"example INVALID JSON  {entry['file']} @ {entry['heading']!r}: {exc}")
            failures += 1
            continue
        validator = Draft202012Validator(json.loads(schema_path.read_text(encoding="utf-8")))
        errors = sorted(validator.iter_errors(instance), key=lambda e: e.json_path)
        if errors:
            print(f"example FAIL   {entry['file']} @ {entry['heading']!r} vs {entry['schema']}")
            for err in errors:
                print(f"    {err.json_path}: {err.message}")
            failures += 1
        else:
            print(f"example OK     {entry['file']} @ {entry['heading']!r}")

        for variant in entry.get("mustReject", []):
            label = f"{entry['file']} @ {entry['heading']!r}: {variant['name']}"
            try:
                mutated = apply_patch(instance, variant["patch"])
            except PatchError as exc:
                print(f"variant BROKEN {label}: {exc}")
                failures += 1
                continue
            if next(validator.iter_errors(mutated), None) is None:
                print(f"variant FAIL   {label}: accepted by {entry['schema']}")
                failures += 1
            else:
                print(f"variant OK     {label}: refused")

    if failures:
        print(f"\n{failures} failure(s)")
        return 1
    print("\nall schemas and mapped examples valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
