#!/usr/bin/env python3
"""Assert that .pre-push-review-not-required names the scripts this repository runs.

The file at the root of this repository says why the pre-push review phases
that exercise an installed tool do not apply here, and says what does run. It
used to call the repository docs-only, with "No CLI, build, test suite, or
runnable artifacts", while scripts/ held the checks and their tests. This
check holds what the file says to the tree it sits in:

    python3 scripts/check_review_marker.py [--root <tree>]

A backticked span of the file that holds a "/", no whitespace and no "://" is
a path relative to the tree, matched one "/"-separated part at a time: a part
holding *, ? or [ is an fnmatch pattern, so * never crosses a "/", and any
other part names an entry exactly, case included. Three rules:

  [unmatched]  a path that matches no file or directory of the tree, or that
               leaves it (an absolute path, or one with a ".." part).
  [unnamed]    a file directly under scripts/, dotfiles aside, that no path of
               the file matches. A path that matches a directory names none of
               the files in it, so `scripts/` alone names no script.
  [denied]     while scripts/ holds such a file, "no", "without" or "neither"
               opening a list in which an item begins with "tests", "test
               suite", "test suites", "scripts", "checks", "runnable",
               "executable" or "executables". The list runs to the end of its
               clause (".", ";", ":" or a parenthesis) and splits at commas and
               at "and", "or" and "nor"; backticked spans are not read as words.

The file is optional: a tree without it passes, since only what it says is
checked. A file that is not UTF-8 text, or a directory in its place, fails as
[unreadable]. Each failure is reported as file:line, as the file alone when it
is unreadable, or as the path of the unnamed script, with its rule in brackets.

Exit 0 when the file agrees with the tree, 1 when it does not, 2 on a usage
error.
"""

import argparse
import fnmatch
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

MARKER = ".pre-push-review-not-required"
SCRIPTS_DIR = "scripts"

CODE_RE = re.compile(r"`([^`\n]+)`")
MAGIC = frozenset("*?[")
NEGATION_RE = re.compile(r"\b(?:no|without|neither)\s+(?P<list>[^.;:()]*)", re.IGNORECASE)
ITEM_SPLIT_RE = re.compile(r",|\b(?:and|or|nor)\b", re.IGNORECASE)
DENIED_RE = re.compile(
    r"(?:tests|test suites?|scripts|checks|runnable|executables?)\b", re.IGNORECASE
)


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def path_spans(text):
    """(line, span) for each backticked span of text that is a path."""
    for m in CODE_RE.finditer(text):
        span = m.group(1)
        if "/" in span and "://" not in span and not any(c.isspace() for c in span):
            yield line_of(text, m.start()), span


def match(root, span):
    """The entries of the tree a path matches, or None when the path leaves the tree."""
    pure = pathlib.PurePosixPath(span)
    if pure.is_absolute() or ".." in pure.parts:
        return None
    found = [root]
    for part in pure.parts:
        magic = bool(MAGIC & set(part))
        found = [
            entry
            for base in found
            if base.is_dir()
            for entry in sorted(base.iterdir())
            if (fnmatch.fnmatchcase(entry.name, part) if magic else entry.name == part)
        ]
    return found


def scripts_in(root):
    """Files directly under scripts/, dotfiles aside, as tree-relative POSIX paths."""
    folder = root / SCRIPTS_DIR
    if not folder.is_dir():
        return []
    return sorted(
        f"{SCRIPTS_DIR}/{p.name}"
        for p in folder.iterdir()
        if p.is_file() and not p.name.startswith(".")
    )


def check(root):
    """(failures, scripts under scripts/), or None when the tree has no marker file."""
    marker = root / MARKER
    if not marker.exists():
        return None
    scripts = scripts_in(root)
    if not marker.is_file():
        return [f"{MARKER} [unreadable] not a regular file"], scripts
    try:
        text = marker.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        return [f"{MARKER} [unreadable] not UTF-8 text: {exc}"], scripts

    failures = []
    named = set()
    for line, span in path_spans(text):
        found = match(root, span)
        if not found:
            how = "leaves the tree" if found is None else "matches no file or directory of the tree"
            failures.append(f"{MARKER}:{line} [unmatched] `{span}` {how}")
            continue
        named |= {entry.relative_to(root).as_posix() for entry in found if entry.is_file()}

    for script in scripts:
        if script not in named:
            failures.append(f"{script} [unnamed] no backticked path in {MARKER} matches it")

    if scripts:
        masked = CODE_RE.sub(lambda m: "#" * len(m.group(0)), text)
        for m in NEGATION_RE.finditer(masked):
            items = (item.strip() for item in ITEM_SPLIT_RE.split(m.group("list")))
            term = next((hit.group(0) for hit in map(DENIED_RE.match, items) if hit), None)
            if term is not None:
                clause = " ".join(m.group(0).split())
                failures.append(
                    f"{MARKER}:{line_of(masked, m.start())} [denied] {clause!r} denies {term!r}, "
                    f"while {SCRIPTS_DIR}/ holds {len(scripts)} file(s)"
                )
    return failures, scripts


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=str(ROOT), help="tree to check (default: this repository)")
    args = ap.parse_args()
    root = pathlib.Path(args.root).resolve()
    if not root.is_dir():
        ap.error(f"--root {args.root} is not a directory")

    result = check(root)
    if result is None:
        print(f"review marker ok: the tree has no {MARKER}, so there is nothing to check")
        return 0
    failures, scripts = result
    if failures:
        print(f"{MARKER} disagrees with the tree:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        print(
            f"\nName each file under {SCRIPTS_DIR}/ with a backticked path or glob, name only "
            "paths that exist, and do not say the repository has no tests or scripts while "
            "it has them.",
            file=sys.stderr,
        )
        return 1

    print(
        f"review marker ok: every backticked path in {MARKER} exists, and they name "
        f"the {len(scripts)} file(s) under {SCRIPTS_DIR}/"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
