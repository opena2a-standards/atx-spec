#!/usr/bin/env python3
"""Assert that each shell block of the documents changes only into directories it makes.

A reader runs a command block as written, often in a fresh shell and with one
section in front of them. The cross-issuer-key block of docs/use-cases.md read

    cd atx-conformance/verifiers/go
    go run . ../../fixtures/cross-issuer-key.json

with no clone step. In a fresh shell the cd failed and go run then found no
go.mod; in the shell that the block before it had left inside its clone, the
cd printed an error line that the quoted output does not show. This check reads
each block as if it ran from an empty directory:

    python3 scripts/check_command_blocks.py [--root <tree>]

One rule, checked over every Markdown file in the tree (hidden directories
such as .git and a CI checkout of the conformance suite are skipped, and so is
node_modules):

  unmade   In a fenced code block whose info string's first word is sh, bash,
           shell or zsh, in any case, a cd to a relative path lands in the
           directory the block starts in, or in or below a directory that an
           earlier command of the block made. A command whose first two words
           are git clone makes the directory its second operand names or,
           with one operand, the directory named by the text after the last
           "/" or ":" of the repository URL, once trailing slashes and a
           trailing "/.git" are removed, less a ".git" suffix; mkdir makes
           each directory it names. The directories above a made one count as
           made. A directory that any other command makes, such as one an
           archive unpacks into, does not count: a block that changes into one
           fails until this check reads that command.

How a block is read. As in CommonMark, a fence is a run of three or more
backticks or tildes indented at most three spaces, and a backtick fence's info
string holds no backtick; a block closes on a fence of the same character, at
least as long as the one that opened it, with nothing after it but white space,
or at the end of the file. A line indented four or more spaces, or by a tab,
neither opens nor closes a fenced block. Each block starts from an empty
directory of its own: nothing an earlier block made or did carries over.

A line of the block is split into words by POSIX shell rules, using Python's
shlex: quotes are removed, and an unquoted "#" starts a comment, inside a word
too. A line that ends in an unescaped backslash, or that leaves a quote open,
is read together with the next one, and the lines of a here-document are
skipped. A word made only of the characters ;, &, |, <, >, ( and ) ends a
command, and outside quotes a run of them is always such a word; a cd inside
parentheses holds only until the closing one. A command's leading variable
assignments and the reserved words !, {, }, if, then, elif, else, do, while,
until and time are passed over to reach its first word. Options of cd, git
clone and mkdir are skipped, together with the value of a git clone or mkdir
option that takes one as the next word. Commands other than cd, git clone,
mkdir, pushd and popd are not interpreted.

Where the shell stands is not known after a cd with no operand, to "-", to an
absolute path, to a path that starts with "~" or holds "$", a backtick, "*",
"?" or "[", or to a path that leaves the directory the block starts in; after
pushd or popd; and after a cd the rule reports. A cd made while that is not
known is not checked.

CHANGELOG.md and errata/ are not checked: they record what earlier text said,
and an erratum quotes the published text verbatim by design.

Each failure is reported as file:line with its rule in brackets; the line is
the first line of the read-together line that holds the cd. A file that is not
UTF-8 text fails as [encoding].

Exit 0 when every file passes, 1 when a file fails or the tree holds no
Markdown file, and 2 on a usage error.
"""

import argparse
import pathlib
import re
import shlex
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

FENCE_RE = re.compile(r"^(`{3,}|~{3,})(.*)$")
SHELLS = {"sh", "bash", "shell", "zsh"}
OPERATOR_CHARS = set("();<>|&")
RESERVED = {"!", "{", "}", "if", "then", "elif", "else", "do", "while", "until", "time"}
ASSIGNMENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
# A cd target holding one of these depends on the reader's shell, not on the block.
UNKNOWN_RE = re.compile(r"[$`*?\[]")
# Options that take their value as the next word when not written --option=value,
# as `git clone -h` (git 2.53) and mkdir(1) list them.
CLONE_VALUE_OPTIONS = {
    "-b", "--branch", "--bundle-uri", "-c", "--config", "--depth", "--filter", "-j", "--jobs",
    "-o", "--origin", "--ref-format", "--reference", "--reference-if-able", "--revision",
    "--separate-git-dir", "--server-option", "--shallow-exclude", "--shallow-since",
    "--template", "-u", "--upload-pack",
}
MKDIR_VALUE_OPTIONS = {"-m", "--mode"}
HISTORY = {"CHANGELOG.md"}
HISTORY_DIRS = {"errata"}


def markdown_files(root):
    """Every *.md file under root, skipping hidden directories and history, in a stable order."""
    found = []
    for path in sorted(root.rglob("*.md")):
        rel = path.relative_to(root)
        if any(part.startswith(".") for part in rel.parts[:-1]):
            continue
        if "node_modules" in rel.parts:
            continue
        if rel.as_posix() in HISTORY or (len(rel.parts) > 1 and rel.parts[0] in HISTORY_DIRS):
            continue
        if path.is_file():
            found.append(path)
    return found


def unindented(line):
    """The line after its indentation, or None when that is more than three columns."""
    body = line.lstrip(" \t")
    # A tab advances to the next multiple of four columns, so a leading tab is
    # already four columns of indentation.
    if len(line[: len(line) - len(body)].expandtabs(4)) > 3:
        return None
    return body


def fence(line):
    """(character, length, text after the run) when the line is a code fence, else None."""
    body = unindented(line)
    if body is None:
        return None
    m = FENCE_RE.match(body)
    if m is None:
        return None
    run, rest = m.groups()
    if run[0] == "`" and "`" in rest:
        return None
    return run[0], len(run), rest


def shell_blocks(lines):
    """[(line number, text), ...] for each fenced block whose info string names a shell."""
    i = 0
    while i < len(lines):
        opened = fence(lines[i])
        if opened is None:
            i += 1
            continue
        char, length, info = opened
        body = []
        i += 1
        while i < len(lines):
            closing = fence(lines[i])
            if closing and closing[0] == char and closing[1] >= length and not closing[2].strip():
                break
            body.append((i + 1, lines[i]))
            i += 1
        i += 1
        if info.split()[:1] and info.split()[0].lower() in SHELLS:
            yield body


def split(text):
    """The words and operators of text, by POSIX shell rules; ValueError on an open quote."""
    lexer = shlex.shlex(text, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    return list(lexer)


def is_operator(token):
    return bool(token) and set(token) <= OPERATOR_CHARS


def heredocs(tokens):
    """(delimiter, tabs stripped) for each here-document a line opens, in order."""
    found = []
    for i, token in enumerate(tokens[:-1]):
        if token != "<<":
            continue
        word, strip_tabs = tokens[i + 1], False
        if word.startswith("-"):
            strip_tabs = True
            word = word[1:] or (tokens[i + 2] if i + 2 < len(tokens) else "")
        if word and not is_operator(word):
            found.append((word, strip_tabs))
    return found


def logical_lines(body):
    """(first line number, tokens) for each read-together line of a block."""
    start, text, pending = None, "", []
    for number, line in body:
        if pending:
            delimiter, strip_tabs = pending[0]
            if (line.lstrip("\t") if strip_tabs else line) == delimiter:
                pending.pop(0)
            continue
        if start is None:
            start, text = number, line
        else:
            text += "\n" + line
        trailing = len(text) - len(text.rstrip("\\"))
        if trailing % 2:
            text = text[:-1]
            continue
        try:
            tokens = split(text)
        except ValueError:
            continue
        yield start, tokens
        pending = heredocs(tokens)
        start, text = None, ""
    if start is not None:
        try:
            yield start, split(text)
        except ValueError:
            pass


def operands(args, value_options=frozenset()):
    """A command's operands: its options skipped, with the value of one that takes the next word."""
    found, skip = [], False
    for i, arg in enumerate(args):
        if skip:
            skip = False
            continue
        if arg == "--":
            return found + args[i + 1:]
        if arg.startswith("-") and arg != "-":
            skip = arg in value_options
            continue
        found.append(arg)
    return found


def clone_directory(url):
    """The directory git clone makes for a repository URL when it is given none."""
    name = url.rstrip("/")
    if name.endswith("/.git"):
        name = name[: -len("/.git")].rstrip("/")
    name = re.split(r"[/:]", name)[-1]
    if name.endswith(".git"):
        name = name[: -len(".git")]
    return name


class Block:
    """Where the shell of one block stands as the block runs from an empty directory."""

    def __init__(self, rel):
        self.rel = rel
        self.cwd = ()  # parts below the starting directory; None once that is not known
        self.made = set()  # first parts of the directories the block made
        self.saved = []  # self.cwd at each open parenthesis
        self.checked = 0
        self.failures = []

    def resolve(self, path):
        """The parts of path below the starting directory, or None where that is not known."""
        if self.cwd is None or path.startswith(("/", "~")) or UNKNOWN_RE.search(path):
            return None
        parts = list(self.cwd)
        for part in path.split("/"):
            if part == "..":
                if not parts:
                    return None
                parts.pop()
            elif part not in ("", "."):
                parts.append(part)
        return tuple(parts)

    def make(self, path):
        target = self.resolve(path) if path else None
        if target:
            self.made.add(target[0])

    def cd(self, number, args):
        found = operands(args)
        target = self.resolve(found[0]) if found and found[0] != "-" else None
        if target is None:
            self.cwd = None
            return
        self.checked += 1
        if target and target[0] not in self.made:
            self.failures.append(
                f"{self.rel}:{number} [unmade] cd {found[0]!r} lands in {'/'.join(target)}, which no "
                f"earlier command of the block makes, so the cd fails when the block runs from an "
                f"empty directory; start the block with the command that makes it, such as the git "
                f"clone of the repository it changes into"
            )
            self.cwd = None
            return
        self.cwd = target

    def run(self, number, words):
        while words and (words[0] in RESERVED or ASSIGNMENT_RE.match(words[0])):
            words = words[1:]
        if not words:
            return
        name, args = words[0], words[1:]
        if name == "cd":
            self.cd(number, args)
        elif name in ("pushd", "popd"):
            self.cwd = None
        elif name == "mkdir":
            for operand in operands(args, MKDIR_VALUE_OPTIONS):
                self.make(operand)
        elif name == "git" and args[:1] == ["clone"]:
            found = operands(args[1:], CLONE_VALUE_OPTIONS)
            if found:
                self.make(found[1] if len(found) > 1 else clone_directory(found[0]))

    def read(self, number, tokens):
        words = []
        for token in tokens:
            if not is_operator(token):
                words.append(token)
                continue
            self.run(number, words)
            words = []
            for char in token:
                if char == "(":
                    self.saved.append(self.cwd)
                elif char == ")" and self.saved:
                    self.cwd = self.saved.pop()
        self.run(number, words)


def check_file(rel, text):
    """(failures, shell blocks read, cd commands checked) for one Markdown file."""
    failures, blocks, checked = [], 0, 0
    for body in shell_blocks(text.splitlines()):
        blocks += 1
        block = Block(rel)
        for number, tokens in logical_lines(body):
            block.read(number, tokens)
        failures.extend(block.failures)
        checked += block.checked
    return failures, blocks, checked


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(ROOT), help="tree to check (default: this repository)")
    args = ap.parse_args()
    root = pathlib.Path(args.root).resolve()

    files = markdown_files(root)
    if not files:
        print(f"no Markdown files under {root}; refusing to pass vacuously", file=sys.stderr)
        return 1

    failures, blocks, checked = [], 0, 0
    for path in files:
        rel = path.relative_to(root).as_posix()
        try:
            text = path.read_bytes().decode("utf-8")
        except UnicodeDecodeError:
            failures.append(f"{rel} [encoding] is not UTF-8 text")
            continue
        found, n_blocks, n_checked = check_file(rel, text)
        failures.extend(found)
        blocks += n_blocks
        checked += n_checked

    if failures:
        print("the command blocks check failed:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print(
        f"command blocks ok: {len(files)} Markdown file(s), {blocks} shell block(s), {checked} "
        f"cd command(s) checked; each lands where its block starts, or in or below a directory "
        f"the block made"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
