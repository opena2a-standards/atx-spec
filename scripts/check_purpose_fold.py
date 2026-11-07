#!/usr/bin/env python3
"""Assert that core.md names every fold the declaredPurpose duplicate-member rule applies.

core.md section 1.3a.2, Member names, makes a PARSE_ERROR of two members of one
object inside declaredPurpose whose names are equal under a fold, and section
1.5.5 restates that rejection. The reference verifiers of atx-conformance judge
the pair with a fixed fold table (foldKey in verifiers/go/verifier/verify.go,
_fold_key in verifiers/python/verify.py): ASCII A to Z to lower case, and two
characters outside ASCII, U+212A KELVIN SIGN to k and U+017F LATIN SMALL LETTER
LONG S to s. A rule that names only the ASCII fold leaves a verifier written
from core.md alone with no rejection ground for a pair the reference verifiers
reject, and section 1.5.5 forbids rejecting for anything else declaredPurpose
holds, so the two reach different verdicts on one credential.

  missing     core.md has a paragraph that says "Inside `declaredPurpose`" and
              "duplicate member". A paragraph is the text between blank lines.
  ascii       That paragraph says "`A` to `Z`".
  unnamed     For each character outside ASCII in the fold table, that
              paragraph names it as U+XXXX (hex digits in either case) and
              names, in backticks, the letter it folds to, within 80
              characters after the code point and before the next U+ that
              four hex digits follow (the U and the digits in either case).
              A letter after that next code point counts for it alone: in
              "each U+212A KELVIN SIGN by `k` and each U+017F LATIN SMALL
              LETTER LONG S by `s`", the `s` names nothing for U+212A.
  ascii-only  No paragraph of core.md that names `declaredPurpose` says that
              two names "differ only in ASCII letter case": that wording
              leaves out the folds outside ASCII.

The fold table is FOLDS below. With --suite <atx-conformance checkout>, the
table is read instead from the rows of the foldKey function of
verifiers/go/verifier/verify.go written as case r == '<rune>': whose next line
that is not blank starts with b.WriteRune('<ASCII letter>'); GO_CASE_RE gives
the rune forms it reads (one character, or a backslash-u or backslash-U
escape). Only a row in code is read: a row whose case, r ==, colon,
b.WriteRune( or closing parenthesis is inside a comment or a string literal
(a row in a block comment or a raw string, or a b.WriteRune line in a block
comment that the case line opens) is not read, and does not replace a row in
code for its character. The function runs from the first line that starts with func foldKey(
outside comments and string literals to the } that closes its body. A brace in
a comment, a string literal or a rune literal does not open or close the body,
and neither does a brace of an interface or struct type in the signature; the
{ that opens the body is on the line the signature ends on, as Go requires. A
row of that form for a character outside ASCII that core.md does not name
fails as [unnamed] when it is the last row of that form for its character; an
earlier row for the same character, and a row for an ASCII character, are not
checked. A fold written in another form is not read, and
core.md is not checked against it: for example two runes in one case, a
backslash-x or octal escape, b.WriteString, a b.WriteRune of a letter outside
ASCII, a default branch that calls unicode.ToLower, or strings.ToLower of the
whole name before the loop. A foldKey with no row of that form for a character
outside ASCII fails as [suite], and so does a verify.go that cannot be read,
that has no func foldKey, or whose func foldKey has no { that opens its body
on the line its signature ends on or no } that closes it.

The check reads words, not meaning: it finds the paragraph and the names it
must hold, and review decides what the paragraph says.

    python3 scripts/check_purpose_fold.py [--root <tree>] [--suite <checkout>]

Exit 0 when core.md passes, 1 otherwise, and 2 on a usage error.
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# The characters outside ASCII that the reference verifiers fold, and the
# ASCII letter each folds to.
FOLDS = {0x212A: "k", 0x017F: "s"}

BLANK_LINE_RE = re.compile(r"\n[ \t]*\r?\n")
ASCII_ONLY_RE = re.compile(r"differ\s+only\s+in\s+ASCII\s+letter\s+case", re.IGNORECASE)
# A code point written as U+ and four hex digits, in either case. The window in
# which the [unnamed] rule looks for the letter a code point folds to ends where
# the next code point starts, so a letter after that one counts for it alone.
CODE_POINT_RE = re.compile(r"U\+[0-9A-Fa-f]{4}", re.IGNORECASE)
GO_FUNC_RE = re.compile(r"^func foldKey\(", re.MULTILINE)
# A Go comment, interpreted or raw string literal, or rune literal, matched from
# its first character. An interpreted string or rune literal that is not closed
# stops before the newline that ends its line; a block comment or raw string
# that is not closed runs to the end of the source.
GO_LITERAL_RE = re.compile(
    r"//[^\n]*"
    r"|/\*.*?(?:\*/|\Z)"
    r"|`[^`]*`?"
    r"|\"(?:\\[^\n]|[^\\\"\n])*\"?"
    r"|'(?:\\[^\n]|[^\\'\n])*'?",
    re.DOTALL,
)
GO_BRACKET_RE = re.compile(r"[()\[\]{}\n]")
# The end of a signature whose next { opens an interface or struct type, not a body.
GO_TYPE_KEYWORD_RE = re.compile(r"(?<!\w)(?:interface|struct)\s*\Z")
# A fold row. The groups named head, colon, call and close must be code, and
# the groups named rune and letter must each be one rune literal of the
# source, so a row in a comment or a string literal is not read.
GO_CASE_RE = re.compile(
    r"(?P<head>case\s+r\s*==\s*)"
    r"(?P<rune>'(?P<rune_value>\\u[0-9A-Fa-f]{4}|\\U[0-9A-Fa-f]{8}|[^'\\])')"
    r"(?P<colon>\s*:)[^\n]*\n\s*"
    r"(?P<call>b\.WriteRune\()(?P<letter>'(?P<letter_value>[A-Za-z])')(?P<close>\))"
)


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def paragraphs(text):
    """(start, end) offsets of each paragraph: the text between blank lines."""
    start = 0
    for m in BLANK_LINE_RE.finditer(text):
        yield start, m.start()
        start = m.end()
    yield start, len(text)


def go_code(source):
    """`source` with each character of its comments, string literals and rune
    literals replaced by a space, newlines kept, so offsets stay the same."""
    return GO_LITERAL_RE.sub(lambda m: re.sub(r"[^\n]", " ", m.group(0)), source)


def go_body_end(code, pos):
    """The offset just past the } that closes the body of the func declaration
    whose parameter list opens just before `pos` in `code` (the output of
    go_code), or None and the brace this check did not find.

    The body opens at the first { outside parentheses, brackets and braces that
    does not follow interface or struct; a newline outside them before it ends
    the signature, as it does in Go, so that declaration has no body."""
    depth = 1
    body = 0
    for m in GO_BRACKET_RE.finditer(code, pos):
        c = m.group(0)
        if body:
            if c == "{":
                body += 1
            elif c == "}":
                body -= 1
                if body == 0:
                    return m.end(), None
        elif c == "\n":
            if depth == 0:
                return None, "{"
        elif c == "{" and depth == 0 and not GO_TYPE_KEYWORD_RE.search(code, pos, m.start()):
            body = 1
        elif c in "([{":
            depth += 1
        else:
            depth -= 1
    return None, "}" if body else "{"


def is_code_row(m, source, code, literals):
    """Whether the GO_CASE_RE match `m` is a row of code: its head, colon, call
    and close groups are not inside a comment or a string literal (go_code
    left them as they are in `source`), and its rune and letter groups each
    span one literal that GO_LITERAL_RE finds in `source` (`literals` maps the
    start of each to its end)."""
    for name in ("head", "colon", "call", "close"):
        if code[m.start(name) : m.end(name)] != source[m.start(name) : m.end(name)]:
            return False
    return all(literals.get(m.start(name)) == m.end(name) for name in ("rune", "letter"))


def suite_folds(suite):
    """The non-ASCII rows of the Go reference verifier's foldKey, or an error string."""
    path = pathlib.Path(suite) / "verifiers" / "go" / "verifier" / "verify.go"
    try:
        source = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        return None, f"cannot read {path} ({exc})"
    code = go_code(source)
    func = GO_FUNC_RE.search(code)
    if not func:
        return None, f"{path} has no func foldKey"
    end, missing = go_body_end(code, func.end())
    if end is None:
        where = f"{path}:{line_of(source, func.start())}"
        if missing == "{":
            return None, (
                f"func foldKey at {where} has no {{ that opens its body "
                "on the line its signature ends on"
            )
        return None, f"func foldKey at {where} has no }} that closes its body"
    literals = {m.start(): m.end() for m in GO_LITERAL_RE.finditer(source)}
    folds = {}
    for m in GO_CASE_RE.finditer(source, func.start(), end):
        if not is_code_row(m, source, code, literals):
            continue
        rune = m.group("rune_value")
        cp = int(rune[2:], 16) if rune.startswith("\\") else ord(rune)
        folds[cp] = m.group("letter_value")
    folds = {cp: letter for cp, letter in folds.items() if cp > 0x7F}
    if not folds:
        return None, f"foldKey in {path} maps no character outside ASCII that this check can read"
    return folds, None


def check(text, folds):
    """The failures of core.md's text under the fold table `folds`."""
    failures = []
    rule = None
    for start, end in paragraphs(text):
        para = text[start:end]
        if rule is None and "Inside `declaredPurpose`" in para and "duplicate member" in para:
            rule = (start, para)
        if "`declaredPurpose`" in para:
            m = ASCII_ONLY_RE.search(para)
            if m:
                failures.append(
                    f"core.md:{line_of(text, start + m.start())} [ascii-only] a paragraph on "
                    f"`declaredPurpose` says {' '.join(m.group(0).split())!r}, which leaves "
                    "out the folds "
                    "outside ASCII (" + ", ".join(f"U+{cp:04X}" for cp in sorted(folds)) + ")"
                )
    if rule is None:
        failures.append(
            "core.md [missing] no paragraph says both \"Inside `declaredPurpose`\" and "
            "\"duplicate member\"; the fold rule of section 1.3a.2 was not found"
        )
        return failures
    start, para = rule
    where = f"core.md:{line_of(text, start)}"
    if "`A` to `Z`" not in para:
        failures.append(f"{where} [ascii] the declaredPurpose fold paragraph does not say `A` to `Z`")
    for cp in sorted(folds):
        letter = folds[cp]
        named = False
        for m in re.finditer(rf"U\+{cp:04X}(?![0-9A-Fa-f])", para, re.IGNORECASE):
            end = m.end() + 80
            nxt = CODE_POINT_RE.search(para, m.end())
            if nxt and nxt.start() < end:
                end = nxt.start()
            if f"`{letter}`" in para[m.end() : end]:
                named = True
                break
        if not named:
            failures.append(
                f"{where} [unnamed] the declaredPurpose fold paragraph does not name U+{cp:04X} "
                f"with the letter it folds to, `{letter}`, within 80 characters after it and "
                "before the next code point"
            )
    return failures


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(ROOT), help="tree to check (default: this repository)")
    ap.add_argument("--suite", help="atx-conformance checkout to read the fold table from")
    args = ap.parse_args()
    root = pathlib.Path(args.root).resolve()

    folds = dict(FOLDS)
    if args.suite:
        folds, err = suite_folds(args.suite)
        if err:
            print(f"the declaredPurpose fold check failed:\n\n  - [suite] {err}", file=sys.stderr)
            return 1

    path = root / "core.md"
    try:
        text = path.read_bytes().decode("utf-8")
    except UnicodeDecodeError as exc:
        print(f"core.md [encoding] not UTF-8 ({exc.reason}); cannot be checked", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"core.md [read] cannot read {path} ({exc.strerror or exc})", file=sys.stderr)
        return 1

    failures = check(text, folds)
    if failures:
        print("the declaredPurpose fold check failed:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1
    names = ", ".join(f"U+{cp:04X} to {folds[cp]}" for cp in sorted(folds))
    print(f"the declaredPurpose fold check passed: core.md names ASCII A to Z and {names}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
