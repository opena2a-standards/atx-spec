#!/usr/bin/env python3
"""Assert the errata object is well formed, indexed, gated and publishable.

An erratum is a correction to published ATX text. It is only worth anything if
the corrected behaviour is observable, so this guard enforces the rules the
errata process is made of rather than leaving them to review:

  - the frontmatter carries exactly the agreed keys, with an id that matches the
    filename and is unique across the directory;
  - errata/README.md is what scripts/gen_errata_index.py produces from the
    erratum files -- a hand-edited index is a failure;
  - core.md's header names the index and the highest incorporated erratum;
  - an accepted or incorporated erratum whose class is not `editorial` names at
    least one conformance fixture, and every fixture it names exists in the
    suite -- "the text changed and nothing tests it" is the failure mode;
  - an accepted or incorporated erratum appears in CHANGELOG.md;
  - a security-class erratum is not still `proposed` in a tree whose core.md
    header already claims it as incorporated;
  - no file under errata/ names an implementation on the roster below (Binding
    Decision 10): the public text says what the spec requires, never who passes.
    A name that is not on the roster passes, so the roster grows with the
    implementations.

This repository does not contain the conformance fixtures, so the suite is
supplied by the caller, exactly as scripts/check_conformance_counts.py takes it:

    python3 scripts/check_errata.py --suite <path-to-atx-conformance>

CI checks out opena2a-standards/atx-conformance at main and passes it here. The
suite is only read when an erratum names a fixture; a tree with no errata --
which is this tree, the mechanism having landed before the errata it will carry
-- passes without one.

The tag half of the pre-mortem guard ("accepted erratum absent from CHANGELOG or
tag") is not implemented: this repository has no tags yet and CI's checkout does
not fetch them. CHANGELOG is checked; the tag check is owed once v1.1.1 exists.

Exit 0 when every rule holds, 1 otherwise. Each failure names the file and the
rule in brackets.
"""

import argparse
import pathlib
import re
import sys

SCRIPTS = pathlib.Path(__file__).resolve().parent
ROOT = SCRIPTS.parent
# The generator is imported, not shelled out to, so the index this checks against
# is the one it would write. No __pycache__ left in a tree the guard then reads.
sys.dont_write_bytecode = True
sys.path.insert(0, str(SCRIPTS))

from gen_errata_index import (  # noqa: E402  (path set above)
    BOOL_KEYS,
    CLASSES,
    ERRATUM_ID_RE,
    ISO_DATE_RE,
    LIST_KEYS,
    FRONTMATTER_KEYS,
    STATUSES,
    FrontmatterError,
    erratum_paths,
    incorporated_through,
    parse_frontmatter,
    render_index,
    title_of,
)

# The core.md header line that points at the index, and the id it carries.
HEADER_RE = re.compile(
    r"^\*\*Errata:\*\* errata/README\.md, incorporated through (ATX-E-\d{4}|none)$"
)

# Binding Decision 10: public spec text names no implementation and no
# implementation status. This list is the roster from the CA ruling and is
# committed here on purpose -- the guard is only as good as the names in it.
# Matching is case-insensitive, which is stricter than the written rule.
BANNED_STRINGS = (
    "@opena2a/atx-verify",
    "atx-conformance Go",
    "atx-conformance Python",
    "AIM Java",
    "Registry Go",
)

# The same roster's OpenA2A AIM (Agent Identity Management) forms. These are
# matched as whole words and case-sensitively, as scripts/check_naming.py reads
# AIM: a case-insensitive substring would fail "claim" and "aimed". The whole
# word AIM also covers "OpenA2A AIM" and "AIM-issued". AIMS, and the IETF's
# "Agent Identity Management System", are different names and pass.
BANNED_WORDS = (
    ("AIM", re.compile(r"\bAIM\b")),
    (
        "Agent Identity Management",
        re.compile(r"\bAgent\s+Identity\s+Management\b(?!\s+System\b)"),
    ),
)

# A status past `proposed`: agreed text, so the fixture and CHANGELOG rules bite.
ACCEPTED_STATUSES = ("accepted", "incorporated")


class Failures:
    """Collected rule violations, reported together rather than one per run."""

    def __init__(self):
        self.items = []

    def add(self, where, rule, message):
        self.items.append((where, rule, message))

    def __bool__(self):
        return bool(self.items)


def rel(path, root):
    try:
        return str(pathlib.Path(path).resolve().relative_to(pathlib.Path(root).resolve()))
    except ValueError:
        return str(path)


def check_frontmatter(where, data, failures):
    """Every key rule for one erratum's frontmatter."""
    keys = set(data)
    for key in sorted(keys - set(FRONTMATTER_KEYS)):
        failures.add(
            where,
            "unknown-key",
            f"frontmatter holds unknown key `{key}`; the erratum keys are "
            f"{', '.join(FRONTMATTER_KEYS)}",
        )
    for key in FRONTMATTER_KEYS:
        if key not in keys:
            failures.add(where, "missing-key", f"frontmatter is missing key `{key}`")

    for key in LIST_KEYS:
        if key in keys and not isinstance(data[key], list):
            failures.add(
                where,
                "bad-type",
                f"`{key}` must be a list (`[]` or `- ` items), got {data[key]!r}",
            )
    for key in BOOL_KEYS:
        if key in keys and not isinstance(data[key], bool):
            failures.add(
                where,
                "bad-type",
                f"`{key}` must be the boolean `true` or `false`, got {data[key]!r}",
            )
    for key in FRONTMATTER_KEYS:
        if key in keys and key not in LIST_KEYS and key not in BOOL_KEYS:
            if not isinstance(data[key], str):
                failures.add(
                    where, "bad-type", f"`{key}` must be a string, got {data[key]!r}"
                )

    if isinstance(data.get("status"), str) and data["status"] not in STATUSES:
        failures.add(
            where,
            "bad-status",
            f"unknown status `{data['status']}`; one of {', '.join(STATUSES)}",
        )
    if isinstance(data.get("class"), str) and data["class"] not in CLASSES:
        failures.add(
            where,
            "bad-class",
            f"unknown class `{data['class']}`; one of {', '.join(CLASSES)}",
        )

    for key in ("affectsDocument", "oldText", "newText"):
        if isinstance(data.get(key), str) and not data[key].strip():
            failures.add(where, "missing-value", f"`{key}` is empty")

    filed = data.get("filed")
    if isinstance(filed, str) and not ISO_DATE_RE.match(filed):
        failures.add(
            where, "bad-date", f"`filed` must be an ISO date (YYYY-MM-DD), got {filed!r}"
        )

    status = data.get("status")
    accepted = data.get("accepted")
    if isinstance(accepted, str) and status in STATUSES:
        if status == "proposed" and accepted.strip():
            failures.add(
                where,
                "accepted-date",
                "`accepted` must be empty while `status` is `proposed`, got "
                f"{accepted!r}",
            )
        if status in ACCEPTED_STATUSES:
            if not accepted.strip():
                failures.add(
                    where,
                    "accepted-date",
                    f"`accepted` must hold an ISO date when `status` is `{status}`",
                )
            elif not ISO_DATE_RE.match(accepted):
                failures.add(
                    where,
                    "bad-date",
                    f"`accepted` must be an ISO date (YYYY-MM-DD), got {accepted!r}",
                )


def check_fixtures(where, data, suite, failures):
    """The rule that makes an erratum observable: class != editorial needs one."""
    status = data.get("status")
    klass = data.get("class")
    fixtures = data.get("fixtures")
    if status not in ACCEPTED_STATUSES or not isinstance(fixtures, list):
        return
    if klass != "editorial" and klass in CLASSES and not fixtures:
        failures.add(
            where,
            "fixture-required",
            f"`{status}` erratum of class `{klass}` names no fixture; an erratum "
            f"whose class is not `editorial` must add or change at least one "
            f"atx-conformance fixture",
        )
    if not fixtures:
        return
    if suite is None:
        failures.add(
            where,
            "suite-missing",
            "names a fixture but no --suite checkout of atx-conformance was given",
        )
        return
    fixtures_dir = pathlib.Path(suite) / "fixtures"
    if not fixtures_dir.is_dir():
        failures.add(
            where,
            "suite-missing",
            f"names a fixture but {fixtures_dir} does not exist",
        )
        return
    for fixture in fixtures:
        if not (fixtures_dir / str(fixture)).exists():
            failures.add(
                where,
                "fixture-missing",
                f"names fixture `{fixture}`, which is not in {fixtures_dir}",
            )


def check_no_implementation_names(errata_dir, root, failures):
    """Binding Decision 10 over every file under errata/, index included."""
    if not errata_dir.is_dir():
        return
    for path in sorted(p for p in errata_dir.rglob("*") if p.is_file()):
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        lowered = text.lower()
        # (name, the text it was found in, offset). lower() can change a
        # string's length, so a line is counted in the text that was searched.
        found = []
        for banned in BANNED_STRINGS:
            if banned.lower() in lowered:
                found.append((banned, lowered, lowered.index(banned.lower())))
        for banned, pattern in BANNED_WORDS:
            m = pattern.search(text)
            if m:
                found.append((banned, text, m.start()))
        for banned, searched, offset in found:
            line = searched[:offset].count("\n") + 1
            failures.add(
                f"{rel(path, root)}:{line}",
                "implementation-name",
                f"public errata text names an implementation or its status "
                f"({banned!r}); the roster and its pass state stay out of the "
                f"published spec",
            )


def check_header(core_text, errata, failures):
    """core.md's one Errata line: present, well formed, and current."""
    lines = core_text.split("\n")
    matches = [(i + 1, ln) for i, ln in enumerate(lines) if ln.startswith("**Errata:**")]
    wanted = incorporated_through(errata)
    if not matches:
        failures.add(
            "core.md",
            "header-errata-line",
            "header block carries no `**Errata:** errata/README.md, incorporated "
            f"through {wanted}` line",
        )
        return None
    if len(matches) > 1:
        failures.add(
            "core.md",
            "header-errata-line",
            f"header carries {len(matches)} `**Errata:**` lines; there is exactly one",
        )
    header_id = None
    for lineno, line in matches:
        m = HEADER_RE.match(line)
        if not m:
            failures.add(
                f"core.md:{lineno}",
                "header-errata-line",
                "line must read `**Errata:** errata/README.md, incorporated through "
                f"<ATX-E-NNNN|none>`, got {line!r}",
            )
            continue
        header_id = m.group(1)
        if header_id != wanted:
            failures.add(
                f"core.md:{lineno}",
                "header-errata-line",
                f"header says incorporated through {header_id}, but the highest "
                f"`incorporated` erratum is {wanted}",
            )
    return header_id


def check_security_order(errata, header_id, root, failures):
    """A security erratum still `proposed` under a header that claims it."""
    if not header_id or header_id == "none":
        return
    for path, data, _, _ in errata:
        erratum_id = data.get("id")
        if data.get("class") != "security" or data.get("status") != "proposed":
            continue
        if not isinstance(erratum_id, str) or not ERRATUM_ID_RE.match(erratum_id):
            continue
        if erratum_id <= header_id:
            failures.add(
                rel(path, root),
                "security-proposed-incorporated",
                f"is a `security` erratum still `proposed`, but core.md's header "
                f"says the document is incorporated through {header_id}, which "
                f"already claims {erratum_id}",
            )


def check_template(errata_dir, root, failures):
    """The template a filer copies has to match the frontmatter contract."""
    template = errata_dir / "TEMPLATE.md"
    if not template.exists():
        failures.add(
            "errata/TEMPLATE.md",
            "template-missing",
            "errata/ carries no TEMPLATE.md for filers to copy",
        )
        return
    where = rel(template, root)
    try:
        data, _ = parse_frontmatter(template.read_text(encoding="utf-8"))
    except FrontmatterError as exc:
        failures.add(where, exc.rule, exc.message)
        return
    if set(data) != set(FRONTMATTER_KEYS):
        failures.add(
            where,
            "template-keys",
            f"template frontmatter keys {sorted(data)} are not the erratum keys "
            f"{sorted(FRONTMATTER_KEYS)}",
        )


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument(
        "--suite",
        default=None,
        help="path to a checkout of opena2a-standards/atx-conformance",
    )
    ap.add_argument(
        "--root",
        default=str(ROOT),
        help="tree to check (default: this repository)",
    )
    args = ap.parse_args()

    root = pathlib.Path(args.root).resolve()
    errata_dir = root / "errata"
    failures = Failures()

    if not errata_dir.is_dir():
        print(f"no errata/ directory under {root}", file=sys.stderr)
        return 1

    # Load every erratum. A file that will not parse is reported and dropped, so
    # one broken erratum does not hide the rest.
    errata = []
    for path in erratum_paths(errata_dir):
        where = rel(path, root)
        try:
            data, body = parse_frontmatter(path.read_text(encoding="utf-8"))
        except FrontmatterError as exc:
            failures.add(where, exc.rule, exc.message)
            continue
        errata.append((path, data, body, title_of(body, str(data.get("id", path.stem)))))

    changelog_path = root / "CHANGELOG.md"
    changelog = (
        changelog_path.read_text(encoding="utf-8") if changelog_path.exists() else ""
    )

    seen_ids = {}
    for path, data, body, title in errata:
        where = rel(path, root)
        check_frontmatter(where, data, failures)

        erratum_id = data.get("id")
        if isinstance(erratum_id, str):
            if not ERRATUM_ID_RE.match(erratum_id):
                failures.add(
                    where,
                    "id-format",
                    f"`id` {erratum_id!r} does not match ^ATX-E-\\d{{4}}$",
                )
            elif erratum_id != path.stem:
                failures.add(
                    where,
                    "id-filename-mismatch",
                    f"`id` is {erratum_id} but the filename stem is {path.stem}; "
                    f"they are the same string",
                )
            if erratum_id in seen_ids:
                failures.add(
                    where,
                    "duplicate-id",
                    f"`id` {erratum_id} is already used by {seen_ids[erratum_id]}",
                )
            else:
                seen_ids[erratum_id] = where

        if not title:
            failures.add(
                where,
                "missing-title",
                "body carries no `# ATX-E-NNNN: <title>` heading for the index",
            )

        check_fixtures(where, data, args.suite, failures)

        if data.get("status") in ACCEPTED_STATUSES and isinstance(erratum_id, str):
            if erratum_id not in changelog:
                failures.add(
                    where,
                    "changelog-missing",
                    f"is `{data['status']}` but {erratum_id} does not appear in "
                    f"CHANGELOG.md; an agreed erratum is a document PATCH and is "
                    f"recorded there",
                )

    # The index is a projection: it is generated, never written.
    index_path = errata_dir / "README.md"
    try:
        wanted = render_index(errata_dir)
    except FrontmatterError:
        wanted = None
    if wanted is not None:
        current = index_path.read_text(encoding="utf-8") if index_path.exists() else None
        if current is None:
            failures.add(
                rel(index_path, root),
                "index-stale",
                "errata/README.md does not exist; run python3 "
                "scripts/gen_errata_index.py",
            )
        elif current != wanted:
            failures.add(
                rel(index_path, root),
                "index-stale",
                "errata/README.md differs from what scripts/gen_errata_index.py "
                "produces from the erratum files; run the generator and commit it",
            )

    core = root / "core.md"
    header_id = None
    if not core.exists():
        failures.add("core.md", "header-errata-line", f"core.md is missing under {root}")
    else:
        header_id = check_header(core.read_text(encoding="utf-8"), errata, failures)
    check_security_order(errata, header_id, root, failures)

    check_template(errata_dir, root, failures)
    check_no_implementation_names(errata_dir, root, failures)

    if failures:
        print("errata are not publishable:\n", file=sys.stderr)
        for where, rule, message in failures.items:
            print(f"  - {where}: [{rule}] {message}", file=sys.stderr)
        print(
            f"\n{len(failures.items)} rule violation(s). The errata rules are "
            f"documented in errata/README.md and enforced by this script.",
            file=sys.stderr,
        )
        return 1

    print(
        f"errata are publishable: {len(errata)} erratum file(s), index current, "
        f"header incorporated through {incorporated_through(errata)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
