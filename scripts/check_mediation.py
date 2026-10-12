#!/usr/bin/env python3
"""Assert the specification never has a verifier ask for a cosignature, and
writes every issuerChain that names the root with the root first.

core.md section 9 keeps every node off the verification path: a verifier makes
no network call to the issuing node, the root node or any other authority while
it verifies, and an issuer that is not on its federation trust list is rejected
as an untrusted issuer (core.md section 7). Cosignatures are made at issuance,
over the same canonical bytes as the first signature. Under atcVersion 1.1
issuerChain is inside those bytes, so the chain is settled, root first
(core.md section 1.3a.2 rule 4), before anyone signs; a chain extended after
the first signature no longer verifies.

Rules, each failure reported as file:line with its rule in brackets:

  verify-path   a sentence that requests, queries, asks for, fetches or obtains
                a cosignature or countersignature does so at issuance: it names
                issuance or the issuing side, or the verb is negated ("does not
                query", "never requests"). The rule applies in a block (a run
                of non-blank lines, so a whole list or a whole paragraph) that
                names a verifier or verification; elsewhere the request is an
                issuance step by context.
  chain-order   an issuerChain written out as a list, `issuerChain = [...]` in
                prose or `"issuerChain": [...]` in JSON, that names the root
                authority did:opena2a:authority:opena2a.org together with other
                authorities names the root first.
  missing       core.md and sovereign-federation.md each say what a verifier
                does with an issuer that is not on its list (the phrase
                "untrusted issuer"), so rewording that away cannot pass
                vacuously.

Every Markdown file in the tree is checked except CHANGELOG.md and errata/,
which record what earlier text said. Hidden directories and node_modules are
skipped. A file that is not UTF-8 fails rather than being skipped.

    python3 scripts/check_mediation.py [--root <tree>]

Exit 0 when every file passes, 1 otherwise.
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

HISTORY = {"CHANGELOG.md"}
HISTORY_DIRS = {"errata"}
REQUIRED = ("core.md", "sovereign-federation.md")

ROOT_AUTHORITY = "did:opena2a:authority:opena2a.org"
ROOT_FORMS = {ROOT_AUTHORITY, "opena2a.org"}

BLOCK_SPLIT_RE = re.compile(r"\n[ \t]*\n")
SEGMENT_SPLIT_RE = re.compile(r"\n(?=[ \t]*(?:\||[-*+][ \t]|\d+[.)][ \t]|#))")
SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+")
VERIFIER_RE = re.compile(r"\bverif(?:ier|iers|ying|ication|ications)\b", re.IGNORECASE)
COSIGN_RE = re.compile(r"\b(?:co-?sign|counter-?sign)\w*", re.IGNORECASE)
REQUEST_RE = re.compile(r"\b(?:request|quer(?:y|ies|ied|ying)|ask|fetch|obtain)\w*", re.IGNORECASE)
ISSUANCE_RE = re.compile(r"\bissu(?:ing|ance)\b", re.IGNORECASE)
NEGATION_RE = re.compile(r"^(?:not|never|nor|cannot|no|without)$", re.IGNORECASE)
WORD_RE = re.compile(r"[\w']+")
NEGATION_WINDOW = 4
CHAIN_RE = re.compile(r"\bissuerChain[`\"']?\s*[=:]\s*\[(?P<body>[^\]]*)\]")
UNLISTED_RE = re.compile(r"\buntrusted\s+issuer\b", re.IGNORECASE)


def markdown_files(root):
    """Every *.md under root, skipping hidden directories and history, in a stable order."""
    found = []
    for path in sorted(root.rglob("*.md")):
        rel = path.relative_to(root)
        if any(part.startswith(".") for part in rel.parts[:-1]):
            continue
        if "node_modules" in rel.parts:
            continue
        if rel.as_posix() in HISTORY or (len(rel.parts) > 1 and rel.parts[0] in HISTORY_DIRS):
            continue
        found.append(path)
    return found


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def pieces(text, split_re):
    """(offset, piece) for each stretch of text between matches of split_re."""
    start = 0
    for m in split_re.finditer(text):
        yield start, text[start:m.start()]
        start = m.end()
    yield start, text[start:]


def sentences(block):
    """(offset, sentence) in a block. A table row, list item or heading starts a
    new segment; a sentence ends at ., ! or ? followed by whitespace."""
    for seg_start, segment in pieces(block, SEGMENT_SPLIT_RE):
        for s_start, sentence in pieces(segment, SENTENCE_SPLIT_RE):
            yield seg_start + s_start, sentence


def negated(sentence, verb_start):
    words = WORD_RE.findall(sentence[:verb_start])[-NEGATION_WINDOW:]
    return any(NEGATION_RE.match(w) for w in words)


def verify_path_failures(rel, text):
    failures = []
    for block_start, block in pieces(text, BLOCK_SPLIT_RE):
        if not VERIFIER_RE.search(block):
            continue
        for s_start, sentence in sentences(block):
            if not COSIGN_RE.search(sentence) or ISSUANCE_RE.search(sentence):
                continue
            for verb in REQUEST_RE.finditer(sentence):
                if negated(sentence, verb.start()):
                    continue
                line = line_of(text, block_start + s_start + verb.start())
                failures.append(
                    f"{rel}:{line} [verify-path] {' '.join(sentence.split())!r} asks for a "
                    f"cosignature beside verification; a verifier makes no network call "
                    f"(core.md section 9) and cosignatures are made at issuance"
                )
                break
    return failures


def chain_order_failures(rel, text):
    failures = []
    for m in CHAIN_RE.finditer(text):
        members = [e.strip().strip("`\"'").strip() for e in m.group("body").split(",")]
        members = [e for e in members if e]
        roots = [i for i, e in enumerate(members) if e in ROOT_FORMS]
        if len(members) > 1 and roots and roots[0] != 0:
            failures.append(
                f"{rel}:{line_of(text, m.start())} [chain-order] issuerChain names the root "
                f"authority at position {roots[0]} of {members}; core.md section 1.3a.2 "
                f"rule 4 puts it first"
            )
    return failures


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(ROOT), help="tree to check (default: this repository)")
    args = ap.parse_args()
    root = pathlib.Path(args.root).resolve()

    files = markdown_files(root)
    if not files:
        print(f"no Markdown files under {root}; refusing to pass vacuously", file=sys.stderr)
        return 1

    failures = []
    texts = {}
    for path in files:
        rel = path.relative_to(root).as_posix()
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError as exc:
            failures.append(f"{rel}:1 [encoding] not UTF-8 ({exc.reason}); cannot be checked")
            continue
        texts[rel] = text
        failures.extend(verify_path_failures(rel, text))
        failures.extend(chain_order_failures(rel, text))

    for rel in REQUIRED:
        if rel not in texts or not UNLISTED_RE.search(texts[rel]):
            failures.append(
                f"{rel} [missing] does not say what a verifier does with an issuer that is "
                f"not on its trust list (no 'untrusted issuer')"
            )

    if failures:
        print("cosignature text puts a node on the verification path or misorders the chain:\n",
              file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print(f"mediation ok: {len(files)} Markdown file(s) checked, no verifier asks for a "
          f"cosignature and every chain naming the root puts it first")
    return 0


if __name__ == "__main__":
    sys.exit(main())
