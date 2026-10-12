#!/usr/bin/env python3
"""Assert every derived figure in scalability.md follows from the inputs it states.

scalability.md says its numbers are computed from the rates, entry sizes and
step costs it gives. This check recomputes each derived figure from those
inputs and fails when the stated figure is not the computed one. A stated
figure passes when it is within TOLERANCE of the computed one, so a figure may
be rounded to two significant digits.

Inputs, each read from the document it lives in:

  steps        the per-step costs of the scalability.md section 2.1 table, up
               to its "Total warm cache" row. The derived figures use the sum
               of every step.
  entry        the transparency log entry size, from "a trillion entry log at
               N bytes per entry".
  credential   the size of the core.md section 1.1 example credential,
               serialized without whitespace, with each signature value
               replaced by a base64 value of the length its algorithm
               produces (Ed25519 64 bytes; ML-DSA-65 3,309 bytes, FIPS 204).
               A credential cannot be smaller than those signature values.
  node         the agent count of the section 8.2 node, from "a node serving
               N agents".

The premises the document states in prose are constants here: one billion
agents, each reissued weekly, a 30 day month and a 365 day year.

Rules, each failure reported as file:line with its rule in brackets:

  total         the "Total warm cache" row states the sum of the steps; every
                number in a range it states is that sum.
  per-core      verifications per second per core are 1,000 ms over the sum.
  per-host      "N cores yield M verifications per second" is N times that.
  verifiers     the verifiers needed for a billion verifications per second
                are a billion over the per-host figure.
  rate          the issuance and log entry rate is a billion over the seconds
                in a week.
  log-size      a trillion entries at the entry size, and a month of entries
                at that rate, are the stated storage.
  credential    a size stated for one credential is not below its signature
                values and not above the section 1.1 example.
  storage       the active set of a billion credentials and the active set of
                the section 8.2 node are their counts times the credential.
  reissuance    a data rate in the section 8.2 reissuance item is an issuance
                rate stated in that item, or the weekly average, times the
                credential.
  log-mirror    the section 8.2 log mirror is a year of the node's weekly
                entries at the entry size.
  capacity      a sentence in section 10 that names conformance says the
                table is not a conformance criterion: no conformance target
                states a capacity.
  missing       each figure above, and each input, is stated, so rewording it
                away cannot pass vacuously.
  encoding      scalability.md and core.md are UTF-8; a file that is not fails
                rather than being skipped.

    python3 scripts/check_scalability.py [--root <tree>]

Exit 0 when every figure follows from its inputs, 1 otherwise.
"""

import argparse
import base64
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

DOC = "scalability.md"
CORE = "core.md"

TOLERANCE = 0.05
AGENTS = 1_000_000_000
WEEK_S = 7 * 86_400
MONTH_S = 30 * 86_400
YEAR_WEEKS = 365 / 7
SIGNATURE_BYTES = {"Ed25519": 64, "ML-DSA-65": 3309}

UNITS = {"bytes": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12}
CORES = {"one": 1, "two": 2, "four": 4, "eight": 8, "sixteen": 16}

NUM = r"(\d[\d,]*(?:\.\d+)?)"
SIZE = NUM + r"\s*(bytes|KB|MB|GB|TB)\b"
ABOUT = r"(?:about\s+|approximately\s+|roughly\s+|~\s*)?"

STEP_ROW_RE = re.compile(r"^\|\s*(?P<step>[^|]+?)\s*\|\s*(?P<cost>\d+(?:\.\d+)?)\s*ms\s*\|")
TOTAL_ROW_RE = re.compile(r"^\|\s*Total warm cache\s*\|(?P<cost>[^|]*)\|", re.IGNORECASE)
MS_RE = re.compile(r"(\d+(?:\.\d+)?)(?=(?:\s+to\s+\d+(?:\.\d+)?)?\s*ms\b)")
PER_CORE_RE = re.compile(ABOUT + NUM + r"\s+verifications\s+per\s+second\s+per\s+core", re.IGNORECASE)
PER_HOST_RE = re.compile(
    r"\b(\w+)\s+cores\s+yields?\s+" + ABOUT + NUM + r"\s+verifications\s+per\s+second", re.IGNORECASE
)
VERIFIERS_RE = re.compile(r"there\s+are\s+" + ABOUT + NUM + r"\s+such\s+verifiers", re.IGNORECASE)
RATE_RE = re.compile(
    r"(?:about|approximately|roughly)\s+" + NUM + r"\s+(?:issuances|entries)\s+per\s+second", re.IGNORECASE
)
TRILLION_RE = re.compile(
    r"trillion\s+entry\s+log\s+at\s+(\d+)\s+bytes\s+per\s+entry\s+is\s+" + SIZE, re.IGNORECASE
)
MONTH_RE = re.compile(r"most\s+recent\s+month\s*\(\s*" + ABOUT + SIZE, re.IGNORECASE)
CREDENTIAL_RES = [
    re.compile(r"^\|\s*Parse ATX JSON\s*\|[^|]*\|(?P<cell>[^|]*)\|", re.IGNORECASE),
    re.compile(r"(?P<cell>each\s+(?:averaging|about|approximately|roughly)\s+" + SIZE + ")", re.IGNORECASE),
    re.compile(r"(?P<cell>active\s+ATX\s+at\s+" + ABOUT + SIZE + r"\s+each)", re.IGNORECASE),
]
CELL_SIZE_RE = re.compile(NUM + r"(?:\s+to\s+" + NUM + r")?\s*(bytes|KB|MB|GB|TB)\b")
ACTIVE_SET_RE = re.compile(r"That\s+is\s+" + ABOUT + SIZE + r"\s+of\s+hot\s+storage", re.IGNORECASE)
NODE_RE = re.compile(r"node\s+serving\s+" + NUM + r"\s+agents", re.IGNORECASE)
NODE_ACTIVE_RE = re.compile(NUM + r"\s+active\s+ATX\s+at[^=\n]*=\s*" + ABOUT + SIZE, re.IGNORECASE)
REISSUANCE_RE = re.compile(r"^\s*[-*+]\s+Weekly\s+reissuance:(?P<item>.*)$", re.IGNORECASE)
ISSUE_RATE_RE = re.compile(NUM + r"\s+(?:issuances\s+)?per\s+second", re.IGNORECASE)
DATA_RATE_RE = re.compile(SIZE + r"\s+per\s+second", re.IGNORECASE)
MIRROR_RE = re.compile(
    r"Transparency\s+log\s+local\s+mirror:\s*" + ABOUT + SIZE + r"\s+per\s+year", re.IGNORECASE
)
SECTION_10_RE = re.compile(r"^##\s+10\.\s")
HEADING_2_RE = re.compile(r"^##\s")
SENTENCE_END_RE = re.compile(r"(?<=[.!?:])\s+")
NEGATION_RE = re.compile(r"\b(?:not|no|neither|nor)\b", re.IGNORECASE)
JSON_BLOCK_RE = re.compile(r"^### 1\.1\b.*?^```json\n(?P<body>.*?)^```", re.MULTILINE | re.DOTALL)


def number(text):
    return float(text.replace(",", ""))


def size(value, unit):
    return number(value) * UNITS[unit]


def agrees(stated, computed):
    return computed > 0 and abs(stated - computed) <= TOLERANCE * computed


def show(value):
    """A computed figure as a reader would write it: three significant digits."""
    if value >= 1e12:
        return f"{value / 1e12:.3g} TB"
    if value >= 1e9:
        return f"{value / 1e9:.3g} GB"
    if value >= 1e6:
        return f"{value / 1e6:.3g} MB"
    if value >= 1e3:
        return f"{value / 1e3:.3g} KB"
    return f"{value:.3g} bytes"


def figure(value):
    return f"{value:,.3g}" if value < 1000 else f"{round(value):,}"


class Check:
    def __init__(self, lines):
        self.lines = lines
        self.failures = []

    def fail(self, line, rule, message):
        where = f"{DOC}:{line}" if line else DOC
        self.failures.append(f"{where} [{rule}] {message}")

    def find(self, pattern):
        """(line, match) for every match of a single-line pattern."""
        return [(n, m) for n, text in enumerate(self.lines, 1) for m in pattern.finditer(text)]

    def first(self, pattern, rule, what):
        found = self.find(pattern)
        if not found:
            self.fail(None, "missing", f"states no {what}; it is checked under [{rule}]")
            return None, None
        return found[0]


def credential_bytes(root):
    """(example size, signature floor) in bytes, or None when core.md has no section 1.1 example."""
    path = root / CORE
    if not path.is_file():
        return None
    match = JSON_BLOCK_RE.search(path.read_text(encoding="utf-8"))
    if not match:
        return None
    try:
        example = json.loads(match.group("body"))
    except json.JSONDecodeError:
        return None
    floor = 0
    for signature in example.get("signatures", []):
        length = SIGNATURE_BYTES.get(signature.get("algorithm"))
        if length is not None:
            signature["value"] = base64.b64encode(bytes(length)).decode()
        floor += len(signature.get("value", ""))
    serialized = json.dumps(example, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return len(serialized), floor


def check_verification(c):
    steps, total = [], None
    for n, text in enumerate(c.lines, 1):
        row = TOTAL_ROW_RE.match(text)
        if row:
            total = (n, row.group("cost"))
            break
        step = STEP_ROW_RE.match(text)
        if step:
            steps.append(float(step.group("cost")))
    if not steps or total is None:
        c.fail(None, "missing", "states no section 2.1 step table ending in a Total warm cache row")
        return
    step_sum = sum(steps)

    line, cell = total
    stated = [float(v) for v in MS_RE.findall(cell)]
    if not stated:
        c.fail(line, "missing", "the Total warm cache row states no cost in ms")
    if any(not agrees(value, step_sum) for value in stated):
        c.fail(line, "total", f"{cell.strip()!r}; the steps above sum to {step_sum:.4g} ms")

    per_core = 1000 / step_sum
    line, m = c.first(PER_CORE_RE, "per-core", "verifications per second per core")
    if m and not agrees(number(m.group(1)), per_core):
        c.fail(line, "per-core", f"{m.group(1)} per core; 1,000 ms over the {step_sum:.4g} ms the "
               f"steps sum to is {figure(per_core)}")

    line, m = c.first(PER_HOST_RE, "per-host", "verifications per second for a multi-core verifier")
    if not m:
        return
    cores = CORES.get(m.group(1).lower()) or (int(m.group(1)) if m.group(1).isdigit() else None)
    if cores is None:
        c.fail(line, "per-host", f"cannot read {m.group(1)!r} as a core count")
        return
    per_host = cores * per_core
    if not agrees(number(m.group(2)), per_host):
        c.fail(line, "per-host", f"{m.group(2)} for {cores} cores; {cores} times {figure(per_core)} "
               f"is {figure(per_host)}")

    line, m = c.first(VERIFIERS_RE, "verifiers", "verifier count for a billion verifications per second")
    if m and not agrees(number(m.group(1)), AGENTS / per_host):
        c.fail(line, "verifiers", f"{m.group(1)} verifiers; a billion over {figure(per_host)} per "
               f"verifier is {figure(AGENTS / per_host)}")


def check_log(c):
    rate = AGENTS / WEEK_S
    found = c.find(RATE_RE)
    if not found:
        c.fail(None, "missing", "states no issuance or log entry rate; it is checked under [rate]")
    for line, m in found:
        if not agrees(number(m.group(1)), rate):
            c.fail(line, "rate", f"{m.group(1)} per second; a billion weekly issuances are "
                   f"{figure(rate)} per second")

    line, m = c.first(TRILLION_RE, "log-size", "transparency log entry size")
    if not m:
        return None
    entry = int(m.group(1))
    if not agrees(size(m.group(2), m.group(3)), 1e12 * entry):
        c.fail(line, "log-size", f"{m.group(2)} {m.group(3)} for a trillion entries; at {entry} bytes "
               f"each that is {show(1e12 * entry)}")

    line, m = c.first(MONTH_RE, "log-size", "hot storage for a month of log entries")
    month = rate * MONTH_S * entry
    if m and not agrees(size(m.group(1), m.group(2)), month):
        c.fail(line, "log-size", f"{m.group(1)} {m.group(2)} for a month; {figure(rate)} entries per "
               f"second for 30 days at {entry} bytes is {show(month)}")
    return entry


def check_storage(c, root, entry):
    measured = credential_bytes(root)
    if measured is None:
        c.fail(None, "missing", f"{CORE} has no section 1.1 example credential to size; "
               f"it is checked under [credential]")
        return
    example, floor = measured

    for pattern in CREDENTIAL_RES:
        found = c.find(pattern)
        if not found:
            c.fail(None, "missing", "states no credential size where it is checked under [credential]")
        for line, m in found:
            cell = m.group("cell")
            sizes = CELL_SIZE_RE.findall(cell)
            if not sizes:
                c.fail(line, "missing", f"{cell.strip()!r} states no credential size")
            for low, high, unit in sizes:
                for value in (low, high) if high else (low,):
                    stated = size(value, unit)
                    if stated < floor or stated > example * (1 + TOLERANCE):
                        c.fail(line, "credential",
                               f"{value} {unit} for one credential; its signature values alone are "
                               f"{floor:,} bytes and the section 1.1 example is {example:,} bytes")

    line, m = c.first(ACTIVE_SET_RE, "storage", "hot storage for the active set")
    if m and not agrees(size(m.group(1), m.group(2)), AGENTS * example):
        c.fail(line, "storage", f"{m.group(1)} {m.group(2)} for a billion credentials; at "
               f"{example:,} bytes each that is {show(AGENTS * example)}")

    line, m = c.first(NODE_ACTIVE_RE, "storage", "active set of the section 8.2 node")
    if m:
        count = number(m.group(1))
        if not agrees(size(m.group(2), m.group(3)), count * example):
            c.fail(line, "storage", f"{m.group(2)} {m.group(3)} for {m.group(1)} credentials; at "
                   f"{example:,} bytes each that is {show(count * example)}")

    line, m = c.first(NODE_RE, "log-mirror", "agent count of the section 8.2 node")
    if not m:
        return
    node = number(m.group(1))

    line, m = c.first(REISSUANCE_RE, "reissuance", "weekly reissuance item in section 8.2")
    if m:
        item = m.group("item")
        rates = [number(r.group(1)) for r in ISSUE_RATE_RE.finditer(item)] + [node / WEEK_S]
        for d in DATA_RATE_RE.finditer(item):
            stated = size(d.group(1), d.group(2))
            if not any(agrees(stated, r * example) for r in rates):
                c.fail(line, "reissuance",
                       f"{d.group(1)} {d.group(2)} per second; at {example:,} bytes per credential, "
                       f"{node:,.0f} weekly issuances are {show(node / WEEK_S * example)} per second, "
                       f"and no other issuance rate in the item gives it")

    line, m = c.first(MIRROR_RE, "log-mirror", "transparency log mirror size for the section 8.2 node")
    mirror = node * YEAR_WEEKS * entry
    if m and entry and not agrees(size(m.group(1), m.group(2)), mirror):
        c.fail(line, "log-mirror", f"{m.group(1)} {m.group(2)} per year; {node:,.0f} weekly entries at "
               f"{entry} bytes for a year is {show(mirror)}")


def check_capacity(c):
    start = next((n for n, text in enumerate(c.lines, 1) if SECTION_10_RE.match(text)), None)
    if start is None:
        c.fail(None, "missing", "has no section 10; it is checked under [capacity]")
        return
    for n in range(start + 1, len(c.lines) + 1):
        text = c.lines[n - 1]
        if HEADING_2_RE.match(text):
            break
        if text.lstrip().startswith("|"):
            continue
        for sentence in SENTENCE_END_RE.split(text):
            if "conformance" in sentence.lower() and not NEGATION_RE.search(sentence):
                c.fail(n, "capacity", f"{sentence.strip()!r} makes the capacity table a conformance "
                       f"criterion; no conformance target states a capacity, so the table is guidance")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(ROOT), help="tree to check (default: this repository)")
    args = ap.parse_args()
    root = pathlib.Path(args.root).resolve()

    failures = []
    path = root / DOC
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        failures.append(f"{DOC} [missing] not found")
        lines = None
    except UnicodeDecodeError as exc:
        failures.append(f"{DOC} [encoding] not UTF-8 ({exc.reason}); cannot check it")
        lines = None

    if lines is not None:
        c = Check(lines)
        check_verification(c)
        entry = check_log(c)
        try:
            check_storage(c, root, entry)
        except UnicodeDecodeError as exc:
            failures.append(f"{CORE} [encoding] not UTF-8 ({exc.reason}); cannot size the credential")
        check_capacity(c)
        failures.extend(c.failures)

    if failures:
        print("scalability figures do not follow from their inputs:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print("scalability ok: every derived figure follows from its stated inputs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
