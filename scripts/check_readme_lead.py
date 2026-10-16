#!/usr/bin/env python3
"""Assert the README opens with its title and a one-sentence description only.

A reader decides from the README's first screen whether to open the
specification, so what stands between the title and the first section heading
is the one sentence that says what the repository covers. Anything longer
belongs under a section or on a page under docs/ that the README links; the
summary that used to sit there is in docs/use-cases.md.

Two rules, checked on README.md at the top of the tree:

  lead      Between the "# " title and the first "## " heading there is one
            paragraph, and it is one sentence. Lines made only of badge images
            and lines that are only an HTML comment do not count. Lines above
            the title, such as the navigation line, are not checked. A second
            paragraph is reported at its first line, a second sentence at the
            line it starts on.
  missing   README.md exists and has a "# " title, a "## " heading after it
            and a description between them, so removing any of them cannot
            pass vacuously.

A heading inside a fenced code block is not a heading. As in CommonMark, a
fence is a run of three or more backticks or tildes indented at most three
spaces, and a backtick fence's info string holds no backtick; a block closes
only on a fence of the same character, at least as long as the one that opened
it, with nothing after it but white space. A line indented four or more spaces,
or by a tab, neither opens nor closes a fenced block.

Nor is a heading inside an HTML block, which, as in CommonMark, opens on a line
indented at most three spaces. A line starting with a "<pre", "<script",
"<style" or "<textarea" tag opens one that closes on the line holding "</pre>",
"</script>", "</style>" or "</textarea>"; "<!--" opens one closed by "-->",
"<?" one closed by "?>", "<!" and a letter one closed by ">", and "<![CDATA["
one closed by "]]>"; the closing line can be the opening one. A line starting
with "<" or "</" and a block-level tag name such as div, details or p, or
holding only one open or closing tag of any other name but those four, opens
one that closes at the next blank line; the second shape opens none directly
under a line of text, meaning a line outside any block that is neither blank
nor a heading. Tag names match in any case.

A sentence ends at ".", "!" or "?" followed by white space and a capital
letter, a digit or the start of Markdown markup. A file that is not UTF-8 is
reported as an [encoding] failure.

    python3 scripts/check_readme_lead.py [--root <tree>]

Exit 0 when the README passes, 1 when it fails or cannot be read, and 2 on a
usage error such as an unknown option.
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
README = "README.md"

FENCE_RE = re.compile(r"^(`{3,}|~{3,})(.*)$")
H1_RE = re.compile(r"^#\s")
H2_RE = re.compile(r"^##\s")
HEADING_RE = re.compile(r"^ {0,3}#{1,6}(?:[ \t]|$)")

# The seven kinds of CommonMark HTML block, in its order: the pattern a line
# opens each with, after at most three spaces of indentation, and the pattern a
# line closes it with, or None when it closes at the first blank line.
RAW_TAGS = r"(?:pre|script|style|textarea)"
BLOCK_TAGS = (
    r"(?:address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd"
    r"|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset"
    r"|h1|h2|h3|h4|h5|h6|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav"
    r"|noframes|ol|optgroup|option|p|param|search|section|summary|table|tbody|td|tfoot|th"
    r"|thead|title|tr|track|ul)"
)
TAG_NAME = r"(?!" + RAW_TAGS + r"(?![A-Za-z0-9-]))[A-Za-z][A-Za-z0-9-]*"
ATTRIBUTE = r"[ \t]+[A-Za-z_:][A-Za-z0-9_.:-]*(?:[ \t]*=[ \t]*(?:[^ \t\"'=<>`]+|'[^']*'|\"[^\"]*\"))?"
LONE_TAG = r"(?:<" + TAG_NAME + r"(?:" + ATTRIBUTE + r")*[ \t]*/?>|</" + TAG_NAME + r"[ \t]*>)[ \t]*$"
HTML_BLOCKS = [
    (re.compile(r"<" + RAW_TAGS + r"(?:[ \t>]|$)", re.I), re.compile(r"</" + RAW_TAGS + r">", re.I)),
    (re.compile(r"<!--"), re.compile(r"-->")),
    (re.compile(r"<\?"), re.compile(r"\?>")),
    (re.compile(r"<![A-Za-z]"), re.compile(r">")),
    (re.compile(r"<!\[CDATA\["), re.compile(r"\]\]>")),
    (re.compile(r"</?" + BLOCK_TAGS + r"(?:[ \t>]|/>|$)", re.I), None),
    # A lone open or closing tag of any other name; it cannot interrupt a paragraph.
    (re.compile(LONE_TAG, re.I), None),
]
IMAGE = r"!\[[^\]]*\]\([^)]*\)"
BADGE_LINE_RE = re.compile(r"^(?:\s*(?:\[" + IMAGE + r"\]\([^)]*\)|" + IMAGE + r"))+\s*$")
COMMENT_LINE_RE = re.compile(r"^\s*<!--.*-->\s*$")
SENTENCE_END_RE = re.compile(r"[.!?](?=\s+[A-Z0-9*_`\[(])")


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


def html_block(line, under_text):
    """Index into HTML_BLOCKS of the kind of HTML block the line opens, or None."""
    body = unindented(line)
    if body is None:
        return None
    last = len(HTML_BLOCKS) - 1
    for kind, (start, _) in enumerate(HTML_BLOCKS):
        if start.match(body) and not (kind == last and under_text):
            return kind
    return None


def headings(lines):
    """(line number of the title, line number of the first section heading after it)."""
    title = section = None
    opening = None  # (character, length) of the fence that opened the current block
    html = None  # index into HTML_BLOCKS of the HTML block the line is in
    under_text = False  # the line before is outside any block and neither blank nor a heading
    for number, line in enumerate(lines, 1):
        if opening is not None:
            char, length, rest = fence(line) or (None, 0, "")
            if char == opening[0] and length >= opening[1] and not rest.strip(" \t"):
                opening = None
            continue
        if html is not None:
            close = HTML_BLOCKS[html][1]
            if close.search(line) if close is not None else not line.strip(" \t"):
                html = None
            continue
        found = fence(line)
        if found is not None:
            opening = found[:2]
            under_text = False
            continue
        html = html_block(line, under_text)
        if html is not None:
            # The line that opens a block can also be the line that closes it.
            close = HTML_BLOCKS[html][1]
            if close is not None and close.search(line):
                html = None
            under_text = False
            continue
        if title is None and H1_RE.match(line):
            title = number
        elif title is not None and H2_RE.match(line):
            section = number
            break
        under_text = bool(line.strip(" \t")) and not HEADING_RE.match(line)
    return title, section


def paragraphs(lines, first, last):
    """[(first line number, [(line number, text), ...])] for lines first..last."""
    out, current = [], []
    for number in range(first, last + 1):
        line = lines[number - 1]
        if not line.strip() or BADGE_LINE_RE.match(line) or COMMENT_LINE_RE.match(line):
            if current:
                out.append((current[0][0], current))
            current = []
            continue
        current.append((number, line))
    if current:
        out.append((current[0][0], current))
    return out


def second_sentence_line(paragraph):
    """Line number on which the paragraph's second sentence starts, or None."""
    text, starts = "", []
    for number, line in paragraph:
        starts.append((len(text), number))
        text += line.strip() + " "
    end = SENTENCE_END_RE.search(text.rstrip())
    if end is None:
        return None
    offset = end.end() + 1
    found = starts[0][1]
    for start, number in starts:
        if start <= offset:
            found = number
    return found


def check(lines):
    """Failures as 'README.md:<line> [rule] message', and a summary for a pass."""
    title, section = headings(lines)
    if title is None:
        return [f"{README}:1 [missing] no '# ' title outside a code block or an HTML block"], None
    if section is None:
        return [f"{README}:{title} [missing] no '## ' section heading after the title"], None

    found = paragraphs(lines, title + 1, section - 1)
    if not found:
        return [f"{README}:{title} [missing] no description between the title and line {section}"], None

    failures = []
    first_line, first = found[0]
    second = second_sentence_line(first)
    if second is not None:
        failures.append(
            f"{README}:{second} [lead] the description above the first section heading "
            "is more than one sentence; keep one and move the rest under a section or to docs/"
        )
    for start, _ in found[1:]:
        failures.append(
            f"{README}:{start} [lead] a second paragraph above the first section heading "
            f"(line {section}); move it under a section or to docs/"
        )
    return failures, (title, first_line, section)


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--root", default=str(ROOT), help="tree to check (default: this repository)")
    args = ap.parse_args()
    path = pathlib.Path(args.root).resolve() / README

    try:
        data = path.read_bytes()
    except OSError as e:
        print(f"  - {README}:1 [missing] {e.strerror or e}", file=sys.stderr)
        return 1
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as e:
        line = data.count(b"\n", 0, e.start) + 1
        print(
            f"  - {README}:{line} [encoding] byte {data[e.start]:#04x} at offset {e.start} "
            "is not UTF-8; save the file as UTF-8",
            file=sys.stderr,
        )
        return 1

    failures, where = check(text.splitlines())
    if failures:
        print("the README does not open with a title and a one-sentence description:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    title, description, section = where
    print(
        f"readme lead ok: title on line {title}, a one-sentence description on line "
        f"{description}, first section heading on line {section}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
