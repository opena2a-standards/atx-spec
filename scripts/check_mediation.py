#!/usr/bin/env python3
"""Assert the specification never has a verifier ask for a cosignature or the
root verify, and writes every issuerChain that names the root with the root
first.

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
                a cosignature or countersignature does so at issuance, or the
                verb is negated. It is at issuance when the sentence says so
                ("at issuance", "during issuance") or the actor named last
                before the verb is the issuing side ("the issuing node
                requests"), not a verifier or verification: "the verifier
                queries the issuing node" fails, since the issuing node is what
                is queried. It is negated when the word before the verb, past
                at most four auxiliaries, adverbs and catenatives such as
                "does", "ever" or "fall back to", is a negation ("does not
                query", "never requests", "does not fall back to asking"); a
                negation in an earlier clause ("if X is not listed, the
                verifier queries") does not count. The rule
                applies in a block (a run of non-blank lines, so a whole list or
                a whole paragraph) that names a verifier or verification;
                elsewhere the request is an issuance step by context.
  root-verifies a sentence that has the root verify: "verified by the root",
                "unverified by root", "the root node verifies" or "the root
                validates". The root cosigns at issuance (core.md section 7
                rule 4) and a verifier checks the signatures a credential
                carries without contacting it, so no credential or cosignature
                is verified, or left unverified, by the root. A sentence passes
                when a negation stands before the participle or the root, read
                as verify-path reads one ("not verified by the root", "no root
                node verifies"), or when it says it is at issuance. "Verified
                by the root's key" and "verified by the root key" name a key,
                not a step the root takes, and pass.
  chain-order   an issuerChain written out as a list, `issuerChain = [...]` in
                prose or `"issuerChain": [...]` in JSON, that names the root
                together with other authorities names the root first. The root
                is did:opena2a:registry:opena2a.org, the registry DID that
                sovereign-federation.md section 3.2 lists as the community
                root, or did:opena2a:authority:opena2a.org, the conformance
                test DID the core.md worked credential keeps, or the bare
                opena2a.org.
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
import bisect
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

HISTORY = {"CHANGELOG.md"}
HISTORY_DIRS = {"errata"}
REQUIRED = ("core.md", "sovereign-federation.md")

ROOT_REGISTRY = "did:opena2a:registry:opena2a.org"
ROOT_AUTHORITY = "did:opena2a:authority:opena2a.org"
ROOT_FORMS = {ROOT_REGISTRY, ROOT_AUTHORITY, "opena2a.org"}

NEWLINE_RE = re.compile(r"\n")
BLOCK_SPLIT_RE = re.compile(r"\n[ \t]*\n")
SEGMENT_SPLIT_RE = re.compile(r"\n(?=[ \t]*(?:\||[-*+][ \t]|\d+[.)][ \t]|#))")
SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+")
VERIFIER_RE = re.compile(r"\bverif(?:ier|iers|ying|ication|ications)\b", re.IGNORECASE)
COSIGN_RE = re.compile(r"\b(?:co-?sign|counter-?sign)\w*", re.IGNORECASE)
REQUEST_RE = re.compile(r"\b(?:request|quer(?:y|ies|ied|ying)|ask|fetch|obtain)\w*", re.IGNORECASE)
# The actors a request can be attributed to: the issuing side or a verifier.
ACTOR_RE = re.compile(
    r"\b(?P<issuing>issu(?:ing|ance))\b|\bverif(?:ier|iers|ying|ication|ications)\b",
    re.IGNORECASE,
)
# A phrase that places the request at issuance wherever it stands.
ISSUANCE_TIME_RE = re.compile(r"\b(?:at|during|upon|on)\s+issuance\b", re.IGNORECASE)
# The root as the one that verifies, passive ("unverified by root") or active
# ("the root node verifies"). The passive form does not match a key ("the
# root's key", with a straight or curly apostrophe, or "the root public key"). A
# negation is looked for before the first word of the match: the participle
# ("not verified by the root") or the root ("no root node verifies").
ROOT_VERIFIES_RE = re.compile(
    r"\b(?:un)?verified\s+by\s+(?:the\s+)?root\b(?!['’]s\b|\s+(?:public\s+)?keys?\b)"
    r"|\broot(?:\s+(?:node|authority))?\s+(?:verif(?:y|ies)|validates?)\b",
    re.IGNORECASE,
)
NEGATIONS = {"not", "never", "nor", "cannot", "can't", "no", "without",
             "don't", "doesn't", "didn't", "won't", "mustn't", "shouldn't"}
# Words that may stand between a negation and the verb it negates: auxiliaries,
# adverbs, and the catenatives of "does not fall back to asking".
AUXILIARIES = {"do", "does", "did", "is", "are", "was", "were", "be", "been", "being",
               "has", "have", "had", "will", "would", "shall", "should", "may", "might",
               "must", "can", "could", "need", "needs", "ever", "also", "then", "itself",
               "themselves", "directly", "separately", "again", "otherwise", "instead",
               "first", "to", "fall", "falls", "back", "try", "tries", "attempt",
               "attempts", "go", "goes", "seek", "seeks"}
# A token is a word or one punctuation character, so a comma or a semicolon
# stops the walk back from a verb.
TOKEN_RE = re.compile(r"[\w']+|[^\w\s]")
NEGATION_WINDOW = 5
# The body stops at either bracket, so a '[' with no ']' after it costs one scan
# to the next bracket rather than one scan to the end of the file per mention.
CHAIN_RE = re.compile(r"\bissuerChain[`\"']?\s*[=:]\s*\[(?P<body>[^\[\]]*)\]")
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


def newline_offsets(text):
    """Where each newline of text stands, found once per file."""
    return [m.start() for m in NEWLINE_RE.finditer(text)]


def line_of(newlines, offset):
    """The line offset sits on, found by bisecting the newline offsets.
    Counting newlines from the start of the file for each failure took time
    quadratic in the number of failures."""
    return bisect.bisect_left(newlines, offset) + 1


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


def negated(tokens, verb_index):
    """True when the token before the verb, past at most NEGATION_WINDOW - 1
    auxiliaries and adverbs, is a negation. Bounded, so a sentence costs time
    linear in its length however many verbs it has."""
    for i in range(verb_index - 1, max(verb_index - 1 - NEGATION_WINDOW, -1), -1):
        word = tokens[i].group(0).lower()
        if word in NEGATIONS:
            return True
        if word not in AUXILIARIES:
            return False
    return False


def at_issuance(actors, verb_start):
    """True when the actor named last before the verb is the issuing side."""
    before = bisect.bisect_left(actors, (verb_start, False))
    return before > 0 and actors[before - 1][1]


def verify_path_failures(rel, text, newlines):
    failures = []
    for block_start, block in pieces(text, BLOCK_SPLIT_RE):
        if not VERIFIER_RE.search(block):
            continue
        for s_start, sentence in sentences(block):
            if not COSIGN_RE.search(sentence) or ISSUANCE_TIME_RE.search(sentence):
                continue
            tokens = list(TOKEN_RE.finditer(sentence))
            token_starts = [t.start() for t in tokens]
            actors = [(m.start(), m.group("issuing") is not None)
                      for m in ACTOR_RE.finditer(sentence)]
            for verb in REQUEST_RE.finditer(sentence):
                if at_issuance(actors, verb.start()):
                    continue
                if negated(tokens, bisect.bisect_left(token_starts, verb.start())):
                    continue
                line = line_of(newlines, block_start + s_start + verb.start())
                failures.append(
                    f"{rel}:{line} [verify-path] {' '.join(sentence.split())!r} asks for a "
                    f"cosignature beside verification; a verifier makes no network call "
                    f"(core.md section 9) and cosignatures are made at issuance"
                )
                break
    return failures


def root_verifies_failures(rel, text, newlines):
    failures = []
    for block_start, block in pieces(text, BLOCK_SPLIT_RE):
        if not ROOT_VERIFIES_RE.search(block):
            continue
        for s_start, sentence in sentences(block):
            matches = list(ROOT_VERIFIES_RE.finditer(sentence))
            if not matches or ISSUANCE_TIME_RE.search(sentence):
                continue
            tokens = list(TOKEN_RE.finditer(sentence))
            token_starts = [t.start() for t in tokens]
            for m in matches:
                if negated(tokens, bisect.bisect_left(token_starts, m.start())):
                    continue
                line = line_of(newlines, block_start + s_start + m.start())
                failures.append(
                    f"{rel}:{line} [root-verifies] {' '.join(sentence.split())!r} has the root "
                    f"verify; the root cosigns at issuance (core.md section 7 rule 4) and a "
                    f"verifier checks the signatures a credential carries without contacting "
                    f"it (core.md section 9)"
                )
                break
    return failures


def chain_order_failures(rel, text, newlines):
    failures = []
    for m in CHAIN_RE.finditer(text):
        members = [e.strip().strip("`\"'").strip() for e in m.group("body").split(",")]
        members = [e for e in members if e]
        roots = [i for i, e in enumerate(members) if e in ROOT_FORMS]
        if len(members) > 1 and roots and roots[0] != 0:
            failures.append(
                f"{rel}:{line_of(newlines, m.start())} [chain-order] issuerChain names the root "
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
        newlines = newline_offsets(text)
        failures.extend(verify_path_failures(rel, text, newlines))
        failures.extend(root_verifies_failures(rel, text, newlines))
        failures.extend(chain_order_failures(rel, text, newlines))

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
          f"cosignature, no sentence has the root verify and every chain naming the root "
          f"puts it first")
    return 0


if __name__ == "__main__":
    sys.exit(main())
