#!/usr/bin/env python3
"""Tests for schemas/atx-credential-v1.1.schema.json against the core.md text.

Each case takes the section 1.1 example credential from core.md, changes one
member, and asserts that the schema accepts the result when the text allows it
and rejects it when the text forbids it. The cited rules are core.md section
1.3a.2 rules 1, 2 and 5 (canonical empties, the full scanSummary, an absent
declaredPurpose), section 1.5.2 (the taskScope grammar, capabilityJustification
keys) and section 14 (capability tokens in the AIP section 4.1 grammar).

    python3 scripts/test_schema.py

Needs python3 and the 'jsonschema' package, as scripts/validate_examples.py
does. Output is TAP-ish: one line per leaf test. Exit 0 when every test passes.
"""

import copy
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from validate_examples import Draft202012Validator, extract_block  # noqa: E402

SCHEMA = json.loads(
    (ROOT / "schemas" / "atx-credential-v1.1.schema.json").read_text(encoding="utf-8")
)
EXAMPLE = json.loads(extract_block(ROOT / "core.md", "### 1.1 ATX schema"))
VALIDATOR = Draft202012Validator(SCHEMA)


def purpose(**changes):
    def apply(d):
        d["declaredPurpose"].update(changes)
    return apply


def member(**changes):
    def apply(d):
        d.update(changes)
    return apply


def scan(**changes):
    def apply(d):
        d["scanSummary"].update(changes)
    return apply


def capabilities(tokens):
    # declaredPurpose is dropped so the case isolates the capabilities pattern.
    def apply(d):
        d["capabilities"] = tokens
        d.pop("declaredPurpose")
    return apply


def drop_purpose(d):
    d.pop("declaredPurpose")


ACCEPT = [
    ("the section 1.1 example as published", lambda d: None),
    ("capabilities empty array (rule 1)", capabilities([])),
    ("capabilities organization-prefixed acme.example/billing:refund (AIP 4.1)",
     capabilities(["acme.example/billing:refund"])),
    ("capabilities multi-label domain prefix acme.co.uk/internal:deploy",
     capabilities(["acme.co.uk/internal:deploy"])),
    ("capabilities action with underscore mcp:tool_use", capabilities(["mcp:tool_use"])),
    ("declaredPurpose absent (rule 5)", drop_purpose),
    ("declaredPurpose null (rule 5)", member(declaredPurpose=None)),
    ("declaredPurpose empty object (rule 5)", member(declaredPurpose={})),
    ("publisherDid empty string (rule 1)", member(publisherDid="")),
    ("buildAttestation empty string (rule 1)", member(buildAttestation="")),
    ("scanSummary.oasbLevel empty string (rule 2)", scan(oasbLevel="")),
    ("scanSummary fully zero-valued (rule 2)",
     scan(hma="", criticalFindings=0, highFindings=0, secretless="", cryptoServe="",
          oasbLevel="")),
    ("taskScopes custom namespace with underscore objective acme:refund_review",
     purpose(taskScopes=["acme:refund_review"])),
    ("capabilityJustification organization-prefixed key",
     purpose(capabilityJustification={"acme.example/billing:refund": ["billing:refund"]})),
]

REJECT = [
    ("taskScopes 9-x:Foo.Bar (section 1.5.2 grammar)", purpose(taskScopes=["9-x:Foo.Bar"])),
    ("taskScopes uppercase namespace Billing:inquiry", purpose(taskScopes=["Billing:inquiry"])),
    ("taskScopes hyphenated namespace billing-ops:inquiry",
     purpose(taskScopes=["billing-ops:inquiry"])),
    ("taskScopes dotted objective billing:refund.full", purpose(taskScopes=["billing:refund.full"])),
    ("taskScopes organization prefix acme.example/billing:refund",
     purpose(taskScopes=["acme.example/billing:refund"])),
    ("capabilities db:Read.* (AIP 4.1 grammar)", capabilities(["db:Read.*"])),
    ("capabilities wildcard action secrets:*", capabilities(["secrets:*"])),
    ("capabilities prefix without a domain acme/billing:refund",
     capabilities(["acme/billing:refund"])),
    ("capabilities uppercase namespace DB:read", capabilities(["DB:read"])),
    ("capabilityJustification key outside the capability grammar",
     purpose(capabilityJustification={"db:Read.*": ["billing:inquiry"]})),
    ("capabilityJustification value outside the taskScope grammar",
     purpose(capabilityJustification={"db:read": ["9-x:Foo.Bar"]})),
    ("declaredPurpose array (rule 5 forbids a non-object)", member(declaredPurpose=[])),
    ("declaredPurpose string (rule 5 forbids a non-object)", member(declaredPurpose="billing")),
    ("publisherDid that is neither a DID nor empty", member(publisherDid="acme-corp")),
    ("scanSummary.oasbLevel L10", scan(oasbLevel="L10")),
    ("scanSummary null (rule 2)", member(scanSummary=None)),
]


def main() -> int:
    count = 0
    failed = 0
    for expected, cases in ((True, ACCEPT), (False, REJECT)):
        for name, change in cases:
            count += 1
            instance = copy.deepcopy(EXAMPLE)
            change(instance)
            errors = list(VALIDATOR.iter_errors(instance))
            verdict = "accepted" if expected else "rejected"
            if (not errors) == expected:
                print(f"ok {count} - {verdict}: {name}")
                continue
            failed += 1
            print(f"not ok {count} - {verdict}: {name}")
            reason = (
                "; ".join(f"{e.json_path}: {e.message}" for e in errors[:3])
                if errors else "the schema accepted it"
            )
            print(f"  ---\n  reason: {reason}\n  ---")
    print(f"1..{count}")
    if failed:
        print(f"# {failed} of {count} failed")
        return 1
    print(f"# all {count} passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
