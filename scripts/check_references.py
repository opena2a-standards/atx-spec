#!/usr/bin/env python3
"""Assert that references in the Markdown documents name what they point at.

Three rules, checked over every Markdown file in the tree except CHANGELOG.md
and errata/, which quote earlier text on purpose (hidden directories such as
.git and a CI checkout of the conformance suite are skipped, and so is
node_modules):

  owner      No reference, in a URL or in link text, names opena2a-org/<repo>
             for a repository in STANDARDS. Those repositories live under
             opena2a-standards. GitHub answers the old path with a 301 for most
             of them and a 404 for the rest, and a redirect lasts only until a
             new repository takes the old name.

  version    A link whose text cites a version (v1.0.0-rc1) and whose target is
             a GitHub repository points at that version's tag, through
             /blob/<version>/ or /tree/<version>. The repository root shows the
             default branch, which carries the next draft rather than the
             version the text cites.

  wire-name  atxVersion appears only in a sentence that also names atcVersion.
             The wire member is atcVersion (core.md section 1.1) and the schema
             rejects atxVersion, so a step that checks atxVersion names a member
             no credential carries. The sentence that records the old alias
             names both.

A link's text may wrap across a line break, and so may a sentence; a sentence
does not cross a blank line, a heading, a list item or a table cell. Each
failure is reported as file:line with its rule in brackets. A file that is not
UTF-8 text is reported as an [encoding] failure.

    python3 scripts/check_references.py [--root <tree>]

Exit 0 when every file passes, 1 when a file fails or cannot be read, and 2 on
a usage error such as an unknown option.
"""

import argparse
import bisect
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Repositories whose home is github.com/opena2a-standards.
STANDARDS = (
    "a2a-idf-conformance",
    "a2a-idf-sdk",
    "aap-conformance",
    "agent-authorization-protocol",
    "agent-governance-spec",
    "agent-identity-protocol",
    "agent-threat-matrix",
    "agent-trust-protocol",
    "ai-safety-txt",
    "aiis-signatures",
    "aip-conformance",
    "atp-conformance",
    "atx-conformance",
    "atx-spec",
    "awesome-agent-souls",
    "did-method-opena2a",
    "opena2a-parity",
    "otel-semconv-agent-identity",
)
OWNER_RE = re.compile(
    r"(?<![\w.-])opena2a-org/("
    + "|".join(re.escape(name) for name in sorted(STANDARDS, key=len, reverse=True))
    + r")(?![\w-]|\.\w)"
)

# An inline link: [text](target). The text may wrap but holds no bracket.
LINK_RE = re.compile(r"\[([^\[\]]*)\]\(\s*<?([^\s()<>]+)")
VERSION_RE = re.compile(r"(?<![\w.-])(v\d+\.\d+\.\d+(?:-[0-9A-Za-z]+(?:\.[0-9A-Za-z]+)*)?)(?![\w-])")
GITHUB_RE = re.compile(r"^https?://github\.com/[^/\s]+/[^/\s#?]+")

ALIAS_RE = re.compile(r"\batxVersion\b")
WIRE_NAME = "atcVersion"

HISTORY = {"CHANGELOG.md"}
HISTORY_DIRS = {"errata"}
SENTENCE_END_RE = re.compile(r"(?<=[.!?])\s+")
BLOCK_START_RE = re.compile(r"^\s*(?:#+\s|\d+\.\s|[-*+]\s|\|)")


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


class Lines:
    """Line numbers by offset, from newline positions found once per file."""

    def __init__(self, text):
        self.newlines = [m.start() for m in re.finditer("\n", text)]

    def of(self, offset):
        return bisect.bisect_left(self.newlines, offset) + 1


def blocks(text):
    """(offset, text) per paragraph, list item or heading, and per table cell."""
    out = []
    start = None
    offset = 0
    for line in text.splitlines(keepends=True):
        if not line.strip() or BLOCK_START_RE.match(line):
            if start is not None:
                out.append((start, text[start:offset]))
            start = None
            if line.lstrip().startswith("|"):
                cell = offset
                for part in line.split("|"):
                    out.append((cell, part))
                    cell += len(part) + 1
                offset += len(line)
                continue
            if line.lstrip().startswith("#"):
                out.append((offset, line))
                offset += len(line)
                continue
        if start is None and line.strip():
            start = offset
        offset += len(line)
    if start is not None:
        out.append((start, text[start:]))
    return out


def sentences(block_offset, block):
    """(offset, sentence) pairs for one block."""
    out = []
    begin = 0
    for m in SENTENCE_END_RE.finditer(block):
        out.append((block_offset + begin, block[begin:m.start()]))
        begin = m.end()
    out.append((block_offset + begin, block[begin:]))
    return out


def report_file(rel, text):
    lines = Lines(text)
    failures = []

    for m in OWNER_RE.finditer(text):
        failures.append(
            f"{rel}:{lines.of(m.start())} [owner] 'opena2a-org/{m.group(1)}' names the old "
            f"owner; the repository is opena2a-standards/{m.group(1)}"
        )

    for m in LINK_RE.finditer(text):
        label, target = m.group(1), m.group(2)
        if not GITHUB_RE.match(target):
            continue
        for v in VERSION_RE.finditer(label):
            version = v.group(1)
            pinned = re.search(
                rf"/(?:blob|tree)/{re.escape(version)}(?:[/#?]|$)", target
            )
            if not pinned:
                failures.append(
                    f"{rel}:{lines.of(m.start())} [version] the link text cites {version} "
                    f"but {target} is not pinned to it; point at /blob/{version}/<file> "
                    f"or /tree/{version}"
                )

    for block_offset, block in blocks(text):
        if not ALIAS_RE.search(block):
            continue
        for offset, sentence in sentences(block_offset, block):
            alias = ALIAS_RE.search(sentence)
            if alias and WIRE_NAME not in sentence:
                failures.append(
                    f"{rel}:{lines.of(offset + alias.start())} [wire-name] 'atxVersion' is "
                    f"not a wire member; the version field is named {WIRE_NAME}"
                )
    return failures


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--root", default=str(ROOT), help="tree to check (default: this repository)")
    args = ap.parse_args()
    root = pathlib.Path(args.root).resolve()

    files = markdown_files(root)
    if not files:
        print(f"no Markdown files under {root}; refusing to pass vacuously", file=sys.stderr)
        return 1

    failures = []
    for path in files:
        rel = path.relative_to(root).as_posix()
        try:
            data = path.read_bytes()
        except OSError as e:
            failures.append(f"{rel}:1 [unreadable] {e.strerror or e}")
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError as e:
            line = data.count(b"\n", 0, e.start) + 1
            failures.append(
                f"{rel}:{line} [encoding] byte {data[e.start]:#04x} at offset {e.start} "
                "is not UTF-8; save the file as UTF-8"
            )
            continue
        failures.extend(report_file(rel, text))

    if failures:
        print("references do not name what they point at:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print(
        f"references ok: {len(files)} Markdown file(s) checked; links name the current "
        f"owner and the cited version, and the version member is called {WIRE_NAME}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
