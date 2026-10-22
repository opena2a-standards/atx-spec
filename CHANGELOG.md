# Changelog

All notable changes to the ATX architecture specifications are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Document
versions follow the OpenA2A spec-family ladder `MAJOR.MINOR.PATCH-{draft|rcN|final}`;
the ATX **credential wire format** version (`atcVersion` `1.0` / `1.1`) is a separate
identifier registered in `core.md` §14.

## [Unreleased]

### Added

- `scripts/check_tbs_member_names.py` + `scripts/test_tbs_member_names.sh`: each TBS key that
  `schemas/atx-credential-v1.1.schema.json` types as an object with `additionalProperties` false
  (a closed object) has a sentence of `core.md` §1.3a.2 that names it and each member the schema
  lists for it in backticks and says "exactly", "none of", "no other" or "any other", or the check
  fails as `[unstated]`; the rule that holds that sentence also has a sentence that names the
  object and says "reject" and `SIGNATURE_INVALID`, or "verbatim", or the check fails as
  `[outcome]`. The keys are read from the included-keys block of §1.3a.2 and typed from the
  schema, so a closed object the schema adds to the TBS joins them; in this tree they are
  `behavioralProfile` and `scanSummary`. A schema that types no TBS key as a closed object fails
  as `[none]`. Against the `core.md` of dff1236 the check reports `[unstated]` for `scanSummary`
  and exits 1; it passes on this tree. It exits 2 on a usage error, needs only python3 and is not
  yet run by CI. The test runs 30 cases with bash and python3; against the `core.md` of dff1236 1
  of them fails, the case that reads the delivered tree. (#113)
- `scripts/check_tbs_timestamps.py` + `scripts/test_tbs_timestamps.sh`: each TBS member, at any
  depth, that `schemas/atx-credential-v1.1.schema.json` types with format `date-time` is named in
  backticks in a sentence of `core.md` §1.3a.2 that says "UTC" and "whole second" or "whole
  seconds", or the check fails as `[missing]`. The members are read from the included-keys block
  of §1.3a.2 and typed from the schema, so a timestamp the schema adds to the TBS joins them; in
  this tree they are `issuedAt`, `expiresAt` and `behavioralProfile.generatedAt`. A sentence
  outside §1.3a.2 does not count, and a schema that types no TBS member as a `date-time` fails as
  `[none]`. With `--suite`, the `expected.canonicalHex` of each atx-conformance `jcs-vectors`
  vector is parsed, and a value of one of those members that is not a `YYYY-MM-DDTHH:MM:SSZ`
  string fails as `[vector]`, as does a TBS that leaves out one that is a top-level key. Against
  the `core.md` of 6a7c32a the check reports `[missing]` for `issuedAt` and `expiresAt`; it passes
  on this tree, and against atx-conformance at 4bdeb7f it reads 20 such values in the 8 vectors.
  The check exits 1 on a failure and 2 on a usage error, needs only python3 and is not yet run by
  CI; the test runs 39 cases with bash and python3, one of them against a real suite checkout when
  `ATX_CONFORMANCE_SUITE` names one. (#106)
- `scripts/check_profile_forms.py` + `scripts/test_profile_forms.sh`: `core.md` §1.3a.2 states
  the form of each `behavioralProfile` member that `schemas/atx-credential-v1.1.schema.json`
  types as integer or as a `date-time` string, or rule 1 defers it to text that does. The
  sentences of §1.3a.2 that name an integer member hold "fraction" and "exponent" between them
  (`[integer-form]`), and those that name a date-time member hold "RFC 3339", "offset" and
  "fraction" (`[date-time-form]`). A sentence of rule 1 that decides a member as another member is
  decided or read ("decided as", "as it reads", "as the verifier decides", "as the verifier
  reads") names at least one schema member in backticks after those words, each of the kind of
  the member it decides and named by sentences of `core.md` that hold the words of that kind
  (`[deferred]`); a member whose deferrals all pass needs no statement of its own. On the previous
  `core.md` the check reports `[deferred]` for `issuedAt`, `expiresAt` and `trustLevel`,
  `[date-time-form]` for `generatedAt` and `[integer-form]` for `observationDays`, and exits 1; on
  this one it exits 0. It exits 2 on a usage error, needs only python3 and is not yet run by CI.
  The test runs 36 cases with bash and python3; against the previous `core.md` 1 of them fails,
  the case that reads the delivered tree. (#105)
- `scripts/check_tbs_numbers.py` + `scripts/test_tbs_numbers.sh`: a sentence that names the TBS
  and says which JSON numbers it holds and no others ("the only JSON numbers in the TBS", "no
  JSON numbers other than") names in backticks each TBS member that
  `schemas/atx-credential-v1.1.schema.json` types as integer or number, `trustScore` apart, and
  names no member the TBS does not hold as a JSON number, other than an object that holds one.
  The members are read from the included-keys block of `core.md` §1.3a.2 and typed from the
  schema, so a numeric member the schema adds joins them, and §1.3a.2 has to hold such a
  sentence. With `--suite`, the `expected.canonicalHex` of each atx-conformance `jcs-vectors`
  vector is parsed, and a JSON number at any other member fails. Markdown files outside
  `CHANGELOG.md` and `errata/` are read. The check exits 1 on a failure and 2 on a usage error,
  needs only python3 and is not yet run by CI; the test runs 39 cases with bash and python3, one
  of them against a real suite checkout when `ATX_CONFORMANCE_SUITE` names one. (#96)
- `scripts/check_revocation_fixture_key.py` + `scripts/test_revocation_fixture_key.sh`: when the
  revocation list (`verifierState.crl`) of an atx-conformance fixture names the revoked agent by
  a member other than the one `core.md` §1.3 step 6 looks up, a sentence of the §12 Coverage
  paragraph names both in backticks, or the check fails as `[unnamed]` (`--suite <path>`). It
  fails as `[stale]` when a Coverage sentence that names the step 6 member also names, in
  backticks, an agent member that no fixture's list uses. A missing step 6 member, Coverage
  paragraph or `fixtures/*.json`, a suite in which no fixture carries a revocation list, a
  fixture that is not JSON and a list whose entries are not an array of objects each fail.
  Against atx-conformance at af921e5 the check reports `[unnamed]` for `agentId` on the previous
  `core.md` and passes on this one. Of the test's 20 cases, one runs the delivered `core.md`
  against a real suite checkout and is skipped unless `ATX_CONFORMANCE_SUITE` names one; the
  others use scratch suites. The check needs only python3 and is not yet run by CI. (#55)
- `scripts/check_review_marker.py` + `scripts/test_review_marker.sh`: each backticked path or
  glob in `.pre-push-review-not-required`, a span that holds a `/` and no whitespace, matches a
  file or directory of the tree, or the check fails as `[unmatched]`; each file directly under
  `scripts/`, dotfiles aside, is matched by one of them, or it fails as `[unnamed]`; and while
  `scripts/` holds a file, no list that "no", "without" or "neither" opens has an item beginning
  with "tests", "test suite", "scripts", "checks", "runnable" or "executable", or it fails as
  `[denied]`. A tree without the file passes. Against the tree at 6d8bd98 the check reports
  `[denied]` for "test suite" and `[unnamed]` for each of the 41 files under `scripts/`; it passes
  on this tree. The check exits 1 on a failure and 2 on a usage error, needs only python3 and is
  not yet run by CI; the test runs 40 cases with bash and python3. (#99)
- `scripts/check_schema_refusals.py` + `scripts/test_schema_refusals.sh`: the sentences of the
  `core.md` §12 Issuer paragraph that say the credential schema refuses account for every
  atx-conformance fixture the schema refuses on its `signatures` member, an Ed25519-only fixture
  that declares `atcVersion` 1.1 through the phrase "Ed25519-only fixtures that declare
  `atcVersion` 1.1" and any other by name, and describe no refusal the suite does not have
  (`--suite <path>`). A missing `core.md`, Issuer paragraph or schema fails, as do a suite with no
  fixtures and a fixture that is not JSON or has no `atx` object. The tests build the failing
  shapes in scratch trees and in scratch suites made from the §1.1 example, and also run against
  a real suite checkout when `ATX_CONFORMANCE_SUITE` names one. The check needs python3 and the
  `jsonschema` package and is not yet run by CI.
- `core.md` §1.3b defines how an authority's DID document declares the threshold key sets that
  §1.3 step 5 checks: a `thresholdKeySets` member, an array of set objects that each hold exactly
  `members`, the `id`s of the verification methods whose public keys are the set's n member keys,
  and `threshold`, the threshold m, an integer from 1 to n. No public key appears twice across a
  document's sets, and a signature that verifies under a member's public key is a signature under
  that member key whatever verification method its `keyId` names. A verifier that finds the
  member malformed treats a signature under any key of that DID document as a signature failure,
  and never reads the member as absent. §1.3 step 5 and `sovereign-federation.md` §2.3 cite
  §1.3b, and §14 registers the member. A DID document without the member declares no threshold
  key set, and the threshold rule of step 5 then rejects nothing. The rejecting one-of-three
  fixture belongs in atx-conformance and is not part of this change. (#74)
- `scripts/check_readme_lead.py` + `scripts/test_readme_lead.sh`: between its `# ` title and
  its first `## ` heading, `README.md` holds one paragraph of one sentence, its description.
  Badge lines and comment-only lines do not count; a second paragraph is reported at its first
  line and a second sentence at the line it starts on, and a README with no title, no section
  heading after it or no description between them fails instead of passing. The check exits 1
  on a failure and 2 on a usage error, needs only python3 and is not yet run by CI; the test
  runs 38 cases with bash and python3.
- `scripts/check_validity_window.py` + `scripts/test_validity_window.sh`: a paragraph, list item,
  heading or table cell in a Markdown file outside `CHANGELOG.md` and `errata/` that names
  `expiresAt` and a check verb (check, verify, validate, compare or reject, in any form) also
  names `issuedAt`, because `core.md` §1.3 step 2 bounds an ATX by both. A list item does not
  borrow `issuedAt` from the next item, a nested item, the next paragraph or another table cell.
  A paragraph, list item, heading or table row that names an expiry or validity window check
  does not call it a single comparison or one comparison, because §1.3 step 2 compares the
  verifier's clock with two bounds; a table row is read whole, so a cost table's step and notes
  cells are read together (#76). Failures are reported as file and line, and a file that is not
  UTF-8 is reported as a failure. The check needs only python3 and is not yet run by CI.
- `scripts/test_conformance_counts.sh`: builds scratch trees and scratch suites of a known size
  and asserts that `scripts/check_conformance_counts.py` fails a stale count in each phrasing it
  reads, naming the file and line, and that `README.md`, `docs/conformance.md` and `core.md` agree
  with the count `core.md` section 12 states. The check takes `--root` for the scratch trees. The
  test needs only bash and python3 and is not yet run by CI.
- `scripts/check_references.py` + `scripts/test_references.sh`: no Markdown file outside
  `CHANGELOG.md` and `errata/` names `opena2a-org/<repo>`, in a URL or in link text, for a
  repository that lives under `opena2a-standards`; a link whose text cites a version such as
  `v1.0.0-rc1` and points at a GitHub repository points at that version's tag through
  `/blob/<version>/` or `/tree/<version>`; and `atxVersion` appears only in a sentence that also
  names the wire member `atcVersion`. Failures are reported as file and line, and a file that is
  not UTF-8 is reported as a failure. The check exits 1 on a failure and 2 on a usage error,
  needs only python3 and is not yet run by CI.
- The breadth class and sensitivity class of each `declaredPurpose` core category. Section
  1.5.3 said each of the 15 categories has both, and section 1.5.4 compares a computed breadth
  with the category's class, but no class value was published anywhere, so the measure could
  not be implemented from the text. Section 1.5.3 now tabulates both classes, and the same table
  is the registry file `schemas/purpose-category-classes-v1.json`. Breadth classes are `narrow`,
  `moderate` and `broad`; sensitivity classes are `standard`, `elevated` and `critical`; a custom
  category stays at `broad` and `critical` until reviewed, and `security-operations` and
  `device-control` are `broad`. Section 1.5.4 now states the measure in full: a capability's
  namespace is everything before its colon, a count of 0 or 1 distinct namespaces is `narrow`, 2
  is `moderate` and 3 or more is `broad`, and the effective class is the broader of that and the
  category's class. `schemas/purpose-breadth-vectors-v1.json` pins three computed breadths: the
  section 1.1 example kept at `moderate`, the section 1.5.4 declaration raised to `broad`, and a
  one-namespace `software-development` declaration not lowered from `broad`. The breadth measure
  is detection input and never an authorization input (section 1.5.1), so no verification verdict
  changes. Neither reference verifier in atx-conformance computes breadth yet.
- `scripts/test_purpose_classes.py`: asserts that the registry file, the section 1.5.3 table and
  the schema's category enum list the same categories in the same order with the same classes,
  that the custom default is the broadest and most sensitive class and the two dual-use
  categories are not narrow, and that each vector's `declaredPurpose` is valid under the schema
  and computes the breadth it pins. It needs python3 and `jsonschema` and is not yet run by CI.
- `scripts/check_signed_fields.py` + `scripts/test_signed_fields.sh`: no sentence in a Markdown
  file outside `CHANGELOG.md` and `errata/` may name a trust level and say it is capped, lowered
  or downgraded, or that it falls back, because section 1.3 says a verifier MUST NOT lower the
  signed level; and no sentence may name capabilities and use a verb form of authorize, because
  section 1.5 says capabilities are attested reach and not permission. A verb with a denial among
  the three words before it passes ("MUST NOT lower"), as does a comparison such as "level 3 or
  lower". A sentence does not cross a blank line, a heading, a list item or a table cell. Failures
  are reported as file and line, and a file that is not UTF-8 is reported as a failure. The check
  runs in time linear in the size of a paragraph, needs only python3 and is not yet run by CI.
- `scanSummary.techniques`, an optional ATX 1.1 member: the Threat Matrix technique IDs
  (`T-NNNN`) that the summarized scan results reference. Section 11 commitment 2 said scan
  results embedded in ATX reference those IDs, but the credential had no member to carry them
  and the schema's `scanSummary` admitted exactly its six members. The schema adds the member as
  an array of unique `T-NNNN` strings, and accepts `null` for it, which rule 6 treats as absent,
  as it accepts a `null` `declaredPurpose`. Section 1.3a.2 rule 6 signs it under 1.1 in the pattern
  rule 5 set for `declaredPurpose`: an absent, `null` or empty array is omitted from the TBS
  `scanSummary`, so every credential without it keeps its exact signed bytes and every pinned
  vector and signature stays valid, and any other present value is signed verbatim in wire
  order, which a verifier may not sort, deduplicate or drop. Section 1.3a.2 rule 2 says the
  member is not one of the six it requires. No verdict on an existing credential changes. The
  conformance fixtures that pin the member's bytes and its injected forms belong in
  atx-conformance and are not part of this change.
- `scripts/test_schema.sh`: takes the section 1.1 example, sets one `scanSummary` member, and
  asserts the schema accepts it or rejects it at the expected JSON path. It covers
  `scanSummary.techniques` (two IDs, an empty array and `null` accepted; a string, a repeated ID
  and malformed IDs rejected) and a member the schema does not define. It needs python3 and
  `jsonschema` and is not yet run by CI.
- `scripts/check_mediation.py` + `scripts/test_mediation.sh`: no Markdown file outside
  `CHANGELOG.md` and `errata/` has a verifier ask for a cosignature. A sentence that requests,
  queries, asks for, fetches or obtains a cosignature or countersignature, in a paragraph or list
  that names a verifier or verification, fails unless it names issuance or the issuing side or
  negates the verb. An `issuerChain` written out as a list that names the root authority together
  with other authorities names the root first, as `core.md` §1.3a.2 rule 4 requires, in prose or
  in JSON. `core.md` and `sovereign-federation.md` must each say what a verifier does with an
  untrusted issuer, so rewording that away fails rather than passing vacuously. Failures are
  reported as file and line, and a file that is not UTF-8 is reported as a failure. The check
  needs only python3 and is not yet run by CI.
- `scripts/check_scalability.py` + `scripts/test_scalability.sh`: a check that recomputes some of
  the figures `scalability.md` states and exits 1 when one of its rules fails. The rules are
  listed under Rules in the script's docstring, which also names figures the check does not read
  and three rewordings it does not catch. It needs only python3 and is not yet run by CI.
- `scripts/check_latency.py` + `scripts/test_latency.sh`: every Markdown file outside
  `CHANGELOG.md` and `errata/` that states a verification latency total states the figure that
  `scalability.md` §2.1 breaks down: under 5 ms on a warm cache and under 50 ms on a cold one. A
  bound counts as a total when its sentence names a warm cache, local verification, a cold cache
  or a cold start, or when it sits in a table row whose first cell is Verification; a per-step
  bound is not a total. A range stated for a total may not end above its figure. In a numbered
  list that states a warm cache total, each per-step bound stays below that total, since the
  steps add up to it. `core.md` must state both totals and `README.md` the warm one, so rewording
  them away fails rather than passing vacuously. Failures are reported as file and line, and a
  file that is not UTF-8 is reported as a failure. The check runs in time linear in the size of
  a paragraph. It needs only python3 and is not yet run by CI.
- `errata/`: published ATX text is now corrected through numbered errata rather
  than silent edits. An erratum is one file, `errata/ATX-E-NNNN.md`, whose
  frontmatter carries `id`, `status`, `class`, `affectsDocument`, `affectsWire`,
  `sections`, `oldText`, `newText`, `fixtures`, `filed` and `accepted` — the
  published text and its replacement verbatim, so a reader can apply the
  correction without judgement. Acceptance of an erratum is a document PATCH on
  the version ladder. A correction to informative text that adds or removes no
  BCP 14 statement is an entry in this changelog, not an erratum.
  `errata/README.md` is generated from those files by
  `scripts/gen_errata_index.py`, states that scope, and is named in `core.md`'s
  header together with the highest incorporated erratum. No erratum has been
  filed yet; this is the mechanism.
- `scripts/check_errata.py` + `scripts/test_errata.sh`, wired into
  `.github/workflows/conformance-counts.yml` after the count check and against
  the same atx-conformance checkout: an erratum whose class is not `editorial`
  cannot be accepted while it names no conformance fixture, or names one the
  suite does not contain — the corrected behaviour has to be observable, not
  just written down. The guard also fails an accepted erratum missing from this
  changelog, a stale index, a frontmatter key that is not in the contract, a
  duplicate or misnamed id, and a `security` erratum still `proposed` under a
  header that already claims it as incorporated. Public errata text names no
  implementation and no pass state, so the guard also fails a file under
  `errata/` that names an implementation on the roster `scripts/check_errata.py`
  commits: OpenA2A AIM (Agent Identity Management), matched case-sensitively as
  the whole word `AIM` or the phrase `Agent Identity Management`, and
  `@opena2a/atx-verify`, `atx-conformance Go`, `atx-conformance Python`,
  `AIM Java` and `Registry Go` in any case. The phrase may wrap across one line
  break but not across a blank line, and the IETF's Agent Identity Management
  System or Systems is a different name and passes. Each name is reported once
  per file, at its file and line, so `AIM Java` is not reported again as `AIM`,
  and a file under `errata/` that is not UTF-8 is reported as a failure rather
  than skipped. A name that is not on the roster passes, so the roster grows
  with the implementations. The public text says what the specification
  requires, and the conformance suite reports who passes.
- `scripts/check_naming.py` + `scripts/test_naming.sh`: every Markdown file in the repository
  must write OpenA2A AIM (Agent Identity Management) in full ahead of any bare AIM. Only text a
  reader sees counts as that expansion: the name inside an HTML comment or a link title, or split
  by a paragraph break, does not. No Markdown file may use either term in the check's `BANNED`
  list: one internal project name (WAI-ARIA, the W3C accessibility specification, is a different
  name and is allowed) and one two-word phrase naming an internal trust component, which fails in
  a descriptive use as well. Failures are reported as file and line, at most 20 per file followed
  by a count of the rest, and a file that is not UTF-8 is reported as a failure. The check exits 1
  on a failure and 2 on a usage error, needs only python3 and is not yet run by CI.
- `scripts/check_pointers.py` + `scripts/test_pointers.sh`: a section that describes a format or
  a decision specified elsewhere must name where it is specified in the section itself, since a
  reader who follows a link to the section does not read the document header. It covers `core.md`
  section 2 item 5 and section 3.3, which must both cite ATP-SPEC v1.0.0-rc1 §8.1 and the
  revocation-list schema `$id`, and `core.md` section 1.5, the section 10 bullet on runtime
  authorization and `README.md`'s third use case, which must each name AAP as the layer that
  decides whether an agent may touch a resource. Those three also call nothing permitted in a
  sentence that does not name AAP. A bulleted list item ends at the next bullet, so AAP named in a
  neighbouring bullet does not count. The HackMyAgent and AIM rows of the section 8 product
  integration map must link the HackMyAgent README and AIP §6.1, which own the check counts and
  the trust score factors, and state no count of checks, factors, payloads, rules or tests
  themselves; a table row ends at its own line, so a link in the next row does not count. A
  missing document or section fails rather than passing vacuously. The check also fails a
  sentence that names the forge lab at specs.opena2a.org/lab/forge, by name or by URL, in any
  Markdown file outside `CHANGELOG.md` and `errata/`, unless that same sentence says that what
  the lab signs is not an ATX credential, since the lab does not verify `JCS(TBS)` of a real
  credential; a file that is not UTF-8 also fails. The check needs only python3 and is not yet
  run by CI.
- `scripts/check_revocation_cursor.py` + `scripts/test_revocation_cursor.sh`: no Markdown file
  outside `CHANGELOG.md` and `errata/` may name a version number for the revocation list, because
  the ATP-SPEC v1.0.0-rc1 §8.1 revocation response has no field to carry one, and no sentence may
  name `agentId` and then the CRL or the revocation list, because each entry in that response
  names the revoked agent by `agentDid` and carries no `agentId`. Failures are reported as file
  and line. The check needs only python3 and is not yet run by CI.
- `scripts/check_revocation_list.py` + `scripts/test_revocation_list.sh`: no Markdown file
  outside `CHANGELOG.md` and `errata/` may say that the revocation list, its response body or its
  cache is signed, in a sentence that names a CRL or a revocation, unless that sentence names
  ATP 1.1, since the §8.1 response has no member for a signature. A file signed for transport,
  such as a CRL published as a signed file, is not that claim and passes. No byte figure stated
  for a revocation entry may be below 227 bytes, the §8.1 example entry as compact JSON, and no
  size stated for a number of revocations may be below that number times 227 bytes.
  `scalability.md` must state both sizes, so rewording them away fails rather than passing
  vacuously. Failures are reported as file and line, and a file that is not UTF-8 is reported as
  a failure. The check needs only python3 and is not yet run by CI.
- `scripts/check_atp_claims.py` + `scripts/test_atp_claims.sh`: no Markdown file outside
  `CHANGELOG.md` and `errata/` may name a negotiation in a sentence that also names ATP or the
  word version, because ATP-SPEC v1.0.0-rc1 defines no negotiation, and none may call a document
  a working group draft (`Working Group draft`, `working-group Internet-Draft` or `WG draft`, in
  any case), because no working group has adopted ATP. A sentence may wrap across lines but not
  across a blank line. Each rule goes in the change that cites the ATP section or the adopted
  draft that makes it obsolete. Failures are reported as file and line. The check needs only
  python3 and is not yet run by CI.
- `scripts/test_schema.py`: takes the §1.1 example credential, changes one member per case, and
  asserts that `schemas/atx-credential-v1.1.schema.json` accepts the result when `core.md` allows
  it and rejects it when `core.md` forbids it. The cases cover the taskScope and capability
  grammars, the keys and values of `capabilityJustification`, an absent, null or empty
  `declaredPurpose`, and the canonical empties of §1.3a.2 rules 1 and 2. It needs python3 and the
  `jsonschema` package, as `scripts/validate_examples.py` does, and is not yet run by CI.
- `scripts/check_coverage_index.py` + `scripts/test_coverage_index.sh`: the sections the
  `core.md` section 12 Coverage paragraph names (`§3.3`) must equal the sections the
  atx-conformance `notCovered` items cite ("section 3.3"), as the family spec-drift check
  `notcovered-index-agrees-with-spec` compares them, so the comparison runs with only the suite
  checked out (`--suite <path>`). A `notCovered` item that cites no section fails, and so does a
  missing Coverage paragraph, `conformance.json` or `notCovered` list. The tests build the
  failing shapes in scratch trees and also run against a real suite checkout when
  `ATX_CONFORMANCE_SUITE` names one. The check needs only python3 and is not yet run by CI.
- `core.md` §1.3 step 5 defines the threshold a verifier checks for a threshold key set held by
  one authority: n keys that each produce their own signature, of which at least m sign. The
  member keys and m are the ones the authority's DID document declares, as resolved in step 3,
  never a threshold the credential states or the number of signatures it carries. Once a
  signature has verified under a member key, the verifier MUST reject the credential unless
  signatures under at least m distinct member keys have verified, so a credential that carries
  one of the three signatures of a two-of-three set is rejected although that one verifies. A
  threshold scheme whose shares combine into one signature under one key is outside the rule.
  Step 7 still counts the set as one authority. Section 3.1 step 8 and `sovereign-federation.md`
  §2.3 name the step. Section 12 lists the threshold among the requirements no fixture
  exercises, and an implementation self-attests it until one does. A credential that carries
  signatures from at least m member keys verifies as before. The rejecting one-of-three fixture
  and the reference verifier checks belong in atx-conformance and are not part of this change.
- `scripts/check_pointers.py` + `scripts/test_pointers.sh`: `core.md` §3.1 step 8,
  `sovereign-federation.md` §2.3 and the fixture paragraph of `docs/conformance.md` each describe
  threshold signing or the suite's threshold fixture, and each must cite §1.3 step 5, where the
  verifier checks the threshold. Without the pointer, "2 of 3" reads as a threshold someone checks.

### Changed

- `scripts/check_tbs_numbers.py` checks the JSON type of the schema root's own `properties`, where
  it looks up the TBS keys, also when the root has a `$ref`. The walk reads no other keyword of a
  node that has a `$ref`, so it did not check that `properties` then, and the lookup ran on what it
  held: a schema whose root has a `$ref` and a `properties` of 5, true, false or null stopped the
  check with a `TypeError` traceback and exit 1, and a `properties` of `["atcVersion"]` or
  `"atcVersion agentId"` was searched as a list or a string, so the check reported `[keys]` for 17
  or 16 of the 18 included keys and none for the keys that list or string holds. Each of those
  shapes now stops the check with one line, as it already did at a root without a `$ref`, such as
  `schemas/atx-credential-v1.1.schema.json cannot be read as a JSON Schema: the schema root has
  "properties": 5, which is not an object`, and exit 1. The delivered tree still passes.
  `scripts/test_tbs_numbers.sh` adds 5 cases, a root `properties` of 5, null and `["atcVersion"]`
  beside a `$ref`, and a one-line count for 5 with and without a `$ref`, and runs 68, one of them
  skipped unless `ATX_CONFORMANCE_SUITE` names a suite checkout; with the check of e212bad, 4 of
  them fail. (#119)
- `scripts/check_schema_refusals.py` checks the credential schema against the JSON Schema 2020-12
  metaschema with `Draft202012Validator.check_schema()` before it validates the fixtures. It built
  the validator without that check, so a `oneOf` of 5 at `scanSummary` or a `type` of 5 at
  `scanSummary.highFindings` stopped the check with a `TypeError` traceback from jsonschema's
  `iter_errors()`, and a `properties` of 5 at the schema root with an `AttributeError` traceback,
  each with exit 1. A schema the metaschema refuses now fails as `[missing]`, as a schema that is
  not JSON does, with exit 1 and one failure line that gives the first place the metaschema
  reports, as a JSON path, and the metaschema's message for it; where that message opens with the
  value in Python notation, the value is written as JSON, cut to 60 characters. For the `oneOf` of
  5 it reports `schemas/atx-credential-v1.1.schema.json [missing] cannot be read as a JSON Schema:
  $.properties.scanSummary.oneOf: 5 is not of type 'array'`. The repository's own tree still
  passes against the test's scratch suite. `scripts/test_schema_refusals.sh` adds 5 cases and runs
  27, one of them skipped unless `ATX_CONFORMANCE_SUITE` names a suite checkout; with the check of
  e212bad, 5 of them fail. (#120)
- `scripts/check_tbs_member_names.py` counts a sentence as the outcome for a closed object only
  when it is also about a member outside the set: it states the set itself, says "none of", "no
  other" or "any other", or says "not" and the one to three words between "is" and "only when" or
  "only if" in a sentence of the same rule that states the set; the `[outcome]` message names
  these. It counted a sentence of that rule that names the object in backticks and says "reject"
  and `SIGNATURE_INVALID`, or "verbatim", whatever it rejected, so the sentence of `core.md`
  §1.3a.2 rule 2 that rejects a `scanSummary` that is not an object, or holds one of the six
  members outside its type, met the `[outcome]` rule: with the sentences of rule 2 from "A
  verifier MUST reject a credential whose `scanSummary` holds a member with any other name"
  through "would ride a valid signature unsigned." deleted, the check exited 0. On that tree it
  now reports `[outcome]` for `scanSummary` at `core.md:269` and exits 1. The delivered tree still
  passes: rule 2 rejects a `scanSummary` member "with any other name", and rule 1 rejects a
  `behavioralProfile` that is "not well formed", the words its member-set sentence puts between
  "is" and "only when". `scripts/test_tbs_member_names.sh` adds 6 cases and runs 36; with the
  check of e212bad, 3 of them fail. (#121)
- `scripts/check_tbs_numbers.py` checks the JSON type of the `type`, `oneOf`, `anyOf`, `allOf` and
  `properties` of each node it walks in the credential schema. It passed `type` to `set.update()`
  and iterated `oneOf`, `anyOf` and `allOf` without that check, and looked the TBS keys up in the
  root `properties` the same way, so a schema that set the `type` of `scanSummary.highFindings` to
  5 or null, or the `oneOf` of `scanSummary` to 5, stopped the check with a `TypeError` traceback
  and exit 1. A `type` that is neither a string nor an array of strings, a `oneOf`, `anyOf` or
  `allOf` that is not an array, or a `properties` that is not an object now stops the check, as a
  schema that is not JSON does, with one line per place that names the schema, the member whose
  schema holds the node (or the schema root) and the keyword with its value, and exit 1. Four
  shapes the check passed before now fail the same way: a `type` of `["integer", 5]` at
  `scanSummary.highFindings`, a `type` of 5 at the schema root, a `oneOf` of `"abc"` at
  `scanSummary`, and a `properties` of `scanSummary` that is an array, which left
  `scanSummary.criticalFindings` and `scanSummary.highFindings` out of the check. The delivered
  tree still passes. `scripts/test_tbs_numbers.sh` adds 7 cases and runs 63, one of them skipped
  unless `ATX_CONFORMANCE_SUITE` names a suite checkout; with the check of 7ada649, 7 of them
  fail. (#117)
- `scripts/check_tbs_numbers.py` reads a `minimum`, `exclusiveMinimum`, `maximum` or
  `exclusiveMaximum` that the schema writes as an integer as the exact int Python's `json` module
  parses, without converting it to a float. It passed each one to `math.isfinite`, which converts
  an int to a float and raises `OverflowError` for one too large to convert, so a schema that set
  the `maximum` of `behavioralProfile.observationDays` to 1 followed by 400 zeros stopped the
  check with a traceback and exit 1; it now reports `[unbounded]` for that member and exits 1. The
  delivered tree still passes. `scripts/test_tbs_numbers.sh` adds 3 cases, a `maximum`, a
  `minimum`, and an `exclusiveMinimum` with an `exclusiveMaximum`, each 1 followed by 400 zeros or
  its negative, and runs 56, one of them skipped unless `ATX_CONFORMANCE_SUITE` names a suite
  checkout; with the check of e3c39fe, 3 of them fail. (#115)
- The stated conformance-suite count follows the suite to **30** fixtures. atx-conformance added
  `fixtures/v1_1-integer-outside-exact-range.json` at 7e1542e, a MUST-REJECT v1.1 credential that
  carries `scanSummary.criticalFindings` 9007199254740993 under an Ed25519 signature over the bytes
  an RFC 8785 serializer that reads each number as an IEEE 754 double writes for it, with
  9007199254740992 in that member, so the signature does not cover the count the credential
  carries. §1.3a.2 rule 3 has a verifier reject that member above 9007199254740991 (2^53 - 1) as a
  signature failure. `README.md` carried the verifier's summary line for 29; `docs/conformance.md`
  carried "29 fixtures" and "29 of 29 PASS"; §12 carried "29 fixtures". Each follows the suite, and
  the fixture joins both fixture enumerations as the last entry of the `v1_1-*` family. Against
  atx-conformance at 7e1542e both reference verifiers report
  `summary: 30 pass, 0 fail (30 fixtures)` and reject the new fixture as `SIGNATURE_INVALID`. No
  normative text changes.
- `core.md` §1.3a.2 rule 3 bounds the integers it names as the only JSON numbers of the TBS
  (`trustLevel`, `scanSummary.criticalFindings`, `scanSummary.highFindings` and
  `behavioralProfile.observationDays`) to an absolute value of at most 9007199254740991
  (2^53 - 1), and `schemas/atx-credential-v1.1.schema.json` gives the last three a `maximum` of
  that value, beside the `minimum` of 0 they had (`trustLevel` already had a `maximum` of 4). Rule
  3 said that leaving only those integers as JSON numbers removes the RFC 8785 ECMAScript
  number-formatting path from cross-language scope, which holds only in the range in which
  implementations agree exactly on the value of an integer (RFC 8259 §6). Outside it they can
  disagree: Node.js 26.12.0, whose `JSON.stringify` formats numbers by the ECMAScript algorithm
  RFC 8785 adopts, writes the parsed `9007199254740993` as `9007199254740992` and
  `1000000000000000000000` as `1e+21`, while Python 3.14.3's `json` module, which keeps the exact
  integer, writes each as given. An issuer MUST NOT emit one of the four outside the range, and a
  verifier MUST reject a credential that carries one there as a signature failure
  (`SIGNATURE_INVALID`): rule 1 makes such an `observationDays` not well formed, rule 2 makes such
  a `criticalFindings` or `highFindings` outside its type, and rule 3 states the rejection for all
  four. Rule 1 still bars a verifier from rejecting a credential on a negative `observationDays`
  within that range: the `minimum` of 0 binds the issuer. jsonschema 4.26.0 (draft
  2020-12) reported no error for the §1.1 example with any of the three set to `9007199254740993`
  or `1000000000000000000000`, and it now rejects each of those six at its `maximum`.
  `scripts/test_schema.py` adds 7 cases and runs 49, of which 5 fail against the schema of
  dff1236; `scripts/test_schema.sh` adds 3 and runs 14, of which 3 fail there: its two new
  rejections and the case that runs `scripts/test_schema.py`. `scripts/check_tbs_numbers.py` adds
  two rules: each schema node that types one of those members as integer or number types it as
  `integer`, with bounds that admit no integer of absolute value above 9007199254740991
  (`[unbounded]`), and a sentence of §1.3a.2 says "9007199254740991" and "reject" (`[range]`);
  with `--suite`, a value of one of those members above that absolute value in a `jcs-vectors`
  vector fails as `[vector]`. Against the `core.md` and schema of dff1236 the check reports
  `[unbounded]` for the three members and `[range]`, and exits 1; it passes on this tree.
  `scripts/test_tbs_numbers.sh` adds 14 cases and runs 53, one of them skipped unless
  `ATX_CONFORMANCE_SUITE` names a suite checkout; with the check, `core.md` and schema of dff1236,
  11 of them fail. The reference verifiers and fixtures in atx-conformance are not part of this
  change. (#112)
- The stated conformance-suite count follows the suite to **29** fixtures. atx-conformance added
  `fixtures/hybrid-pq-only.json` at 50cbe67, a MUST-REJECT v1.0 credential: the v1.0 hybrid
  baseline with its Ed25519 signature removed, so it carries one ML-DSA-65 signature that verifies
  and no Ed25519 signature. §13 requires a verifying Ed25519 entry beside an ML-DSA-65 entry and
  names no `atcVersion`; until this fixture the suite pinned that rule only under `atcVersion` 1.1,
  with `fixtures/v1_1-hybrid-pq-only.json`. `README.md` carried the verifier's summary line for 28;
  `docs/conformance.md` carried "28 fixtures" and "28 of 28 PASS"; §12 carried "28 fixtures" and,
  in its Issuer paragraph, "the four fixtures that carry an ML-DSA-65 signature", where five now
  do. Each follows the suite, and the fixture joins both fixture enumerations beside the hybrid
  case it is cut from. Against atx-conformance at a825ec2 both reference verifiers report
  `summary: 29 pass, 0 fail (29 fixtures)` and reject the new fixture as `SIGNATURE_INVALID`. No
  normative text changes.
- `core.md` §1.3a.2 rule 2: the member names a `scanSummary` may hold are exactly the six members
  and `techniques`, compared exactly, so a name that differs in case is a different member. An
  issuer MUST NOT emit a `scanSummary` member with any other name, and a verifier MUST reject a
  credential whose `scanSummary` holds one as a signature failure (`SIGNATURE_INVALID`), as rule 1
  does for a `behavioralProfile` whose member names are not exactly its three, and MUST NOT drop
  it when it rebuilds the signed bytes. Rule 2 rejected a `scanSummary` that is not an object or
  holds one of the six outside its type, and gave no outcome for a member with another name; the
  TBS `scanSummary` carries only the six and `techniques`, so such a member is in no signed byte,
  and a verifier that drops it accepts a credential carrying a member no signature covers. The
  schema's `additionalProperties` false on `scanSummary` already refused such a member, but rule 2
  did not require a verifier to. §13 names the case beside the other `scanSummary` signature
  failures. The projection of a `scanSummary` that holds only those members is unchanged. The
  reference verifiers and fixtures in atx-conformance are not part of this change. (#113)
- `core.md` §1.3a.2 rule 7: a wire value of `issuedAt`, `expiresAt` or
  `behavioralProfile.generatedAt` whose instant falls in UTC outside the years 0000 to 9999 has no
  `YYYY-MM-DDTHH:MM:SSZ` form, and a verifier MUST reject a credential that carries one rather than
  write a year of more than four digits, or a negative year, into the TBS. An `issuedAt` or
  `expiresAt` that is such a value does not parse, and the credential is rejected at §1.3 step 1;
  a `generatedAt` that is such a value makes the `behavioralProfile` not well formed (rule 1), a
  signature failure (`SIGNATURE_INVALID`). An issuer MUST NOT emit such a value. A numeric offset
  carries a valid RFC 3339 value there: `9999-12-31T23:59:59-01:00` is 10000-01-01T00:59:59 in UTC
  and `0000-01-01T00:00:00+01:00` falls in the year before 0000, and rule 7 stated no outcome for
  either. `scripts/check_tbs_timestamps.py` adds a `[range]` rule: a sentence of §1.3a.2 says
  "UTC", "0000", "9999" and "reject", or the check fails. Against the `core.md` of 0fa8214 it
  reports `[range]`, and it passes on this tree; `scripts/test_tbs_timestamps.sh` adds 9 cases for
  the rule and runs 48, one of them skipped unless `ATX_CONFORMANCE_SUITE` names a suite checkout.
  The reference verifiers in atx-conformance are not part of this change. (#109)
- `core.md` §1.3a.2 rule 7: in the TBS, `issuedAt` and `expiresAt` are each the instant its value
  in the credential denotes, written in UTC to whole seconds (`YYYY-MM-DDTHH:MM:SSZ`), as rule 1
  writes `behavioralProfile.generatedAt`. For all three the projection applies a time-zone offset
  and drops a fractional second instead of rounding it, so two wire values in the same UTC second
  have the same projection and the signature covers these members to the second. The section
  listed `issuedAt` and `expiresAt` among the TBS keys and stated no form for them. Built from the
  `tbs` of atx-conformance's `01-baseline` vector, a TBS that carries the wire value verbatim
  differs from the pinned bytes when that value is `2026-05-23T02:00:00.900+02:00`,
  `2026-05-23T02:00:00+02:00` or `2026-05-23T00:00:00.5Z` in `issuedAt`, or the same three shapes
  in `expiresAt`, and the UTC whole-second projection of each reproduces them. In atx-conformance
  at 4bdeb7f the Go verifier writes the three members with `UTC().Format(time.RFC3339)` and the
  Python verifier with `_format_rfc3339`; Go's `time.Parse(time.RFC3339)` followed by that format,
  and the Python verifier's `_parse_rfc3339` followed by `_format_rfc3339`, each map
  `2026-05-19T02:00:00.900+02:00`, `2026-05-19T00:00:00.999999999Z` and
  `2026-05-18T23:30:00-00:30` to `2026-05-19T00:00:00Z`. The suite's 8 `jcs-vectors` hold these
  members in that form, so no byte vector changes, and none of its 28 fixtures carries a numeric
  offset or a fractional second in them; fixtures that do belong in atx-conformance and are not
  part of this change. (#106)
- `schemas/atx-credential-v1.1.schema.json` accepts a `behavioralProfile` whose value is `null`,
  which `core.md` §1.3a.2 rule 1 treats as absent, as the schema accepts a `null`
  `scanSummary.techniques` (rule 6) and a `null` `declaredPurpose` (rule 5). The schema typed the
  member as an object only, so the §1.1 example with `"behavioralProfile": null` failed
  validation on its type, while the same example with the member omitted validated. The object
  constraints are unchanged, and the member now carries a description that says `null` is
  treated as absent. `scripts/test_schema.py` adds a case that accepts the `null` and two that
  reject an empty object and the string `"null"`; run against the schema at 6a7c32a, 1 of its 42
  cases fails, and all 42 pass on this tree. No normative text changes. (#107)
- `core.md` §1.3a.2 rule 1 states the two forms it used to decide by reference to text that
  states neither. It said `generatedAt` is in the RFC 3339 `date-time` form "decided as the
  verifier decides `issuedAt` and `expiresAt` (§1.3 step 2)", and §1.3 step 2 states a
  validity-window comparison and no date-time grammar; it said `observationDays` is read as an
  integer "decided as it reads `trustLevel`", and no sentence of `core.md` that names `trustLevel`
  says how a number written with a fraction or an exponent part is read. Three bullets of rule 1
  now state them. `generatedAt` matches the RFC 3339 §5.6 `date-time` production with an
  upper-case `T` and `Z` and a second from `00` to `59`, on a day of the Gregorian calendar, with
  optional fractional seconds and then `Z` or a numeric offset. `observationDays` is a JSON number
  written with neither a fraction part nor an exponent part (RFC 8259 §6), decided from the JSON
  text, so `14` is in that form and `14.0`, `1.4e1` and `14E0` are not. The projection writes
  `generatedAt` as the instant it names in UTC to whole seconds, subtracting a numeric offset and
  dropping fractional seconds without rounding, so the signature covers that second and not the
  offset or fractional digits the credential writes; a `generatedAt` whose instant falls outside
  the years `0000` to `9999` in UTC is not well formed. The credential schema's `integer` type
  accepts `14.0` and `1.4e1` (jsonschema 4.26.0, draft 2020-12), and Go's `encoding/json` rejects
  both when it decodes them into an `int` (go1.26.3), so the schema type did not decide the
  reading. For a `generatedAt` already written as `YYYY-MM-DDTHH:MM:SSZ` and an `observationDays`
  written as an integer, the projection the text describes is unchanged. No BCP 14 statement is
  added or removed, and the text this replaces is not in the v1.1.0 `core.md`. (#105)
- `scripts/check_review_marker.py` reads a run of whitespace in an item of a `[denied]` list, line
  breaks included, as one space. Its pattern matched "test suite" and "test suites" only with one
  space between the words, so a `.pre-push-review-not-required` with "There is no test" at the
  end of one line and "suite here." at the start of the next passed, as did one with two spaces
  between "test" and "suite" on one line; each now fails as `[denied]` for 'test suite'. The
  delivered file still passes. `scripts/test_review_marker.sh` adds 3 cases: a line break and two
  spaces between "test" and "suite", and a line break and an indent between "test" and "suites".
  (#102)
- The stated conformance-suite count follows the suite to **28** fixtures. atx-conformance added
  `fixtures/threshold-1of3-cosignature.json`, a MUST-REJECT v1.0 credential: the threshold
  cosignature credential cut to one of its three signatures, the primary's, under a verifier state
  that holds the issuer's three Ed25519 keys and requires two of them. The one signature verifies,
  so a verifier that checks only that every declared signature verifies, and reads no threshold,
  wrongly accepts; §1.3 step 5 rejects the credential unless signatures under at least m distinct
  member keys of the threshold key set verify. `README.md` carried the verifier's summary line for
  27; `docs/conformance.md` carried "27 fixtures" and "27 of 27 PASS"; §12 carried "27 fixtures".
  Each follows the suite, and the fixture joins both fixture enumerations beside the threshold
  cosignature case it is cut from. Against atx-conformance at 3d73f18 both reference verifiers
  report `summary: 28 pass, 0 fail (28 fixtures)` and reject the new fixture as
  `SIGNATURE_INVALID` with the reason `signature threshold not met`. No normative text changes.
- `core.md` §1.3a.2 rule 3 names the JSON numbers the TBS holds once `trustScore` is
  string-encoded: the integers `trustLevel`, `scanSummary.criticalFindings` and
  `scanSummary.highFindings` (rule 2), and `behavioralProfile.observationDays` unless
  `behavioralProfile` is `null` (rule 1). It called `trustLevel` the only JSON number in the TBS,
  while rule 2 puts two integer members in every TBS `scanSummary`, §12 says rule 2 brings
  `criticalFindings` into the TBS as an integer, and the schema types
  `behavioralProfile.observationDays` as an integer. In atx-conformance at ca1ee3e each of the
  eight `jcs-vectors` canonical TBS holds three or four JSON numbers: `trustLevel` and the two
  `scanSummary` integers in all eight, and `behavioralProfile.observationDays` in the four whose
  `behavioralProfile` is an object. The sentence speaks of the TBS of a conforming credential,
  because rule 5 includes a non-object `declaredPurpose` in the TBS verbatim and the suite's
  `v1_1-declared-purpose-number-injected` fixture carries the number 1.5 there. The rest of the
  sentence is unchanged, and no BCP 14 statement is added or removed. (#96)
- `core.md` section 12, Coverage, says that both revocation fixtures give the verifier a
  revocation list, in the suite's own fixture format, whose entries name the revoked agent by the
  credential's `agentId`, the key §1.3 step 6 looked up in the revision of `core.md` the fixtures
  cite (e89bed9), and that the format has no entry member for `agentDid`, the key step 6 now looks
  up. A verifier that looks the agent up by `agentDid` alone, as step 6 says, finds no entry for it
  there, so `revoked-crl-only` pins the verdict of a lookup by `agentId` and not that of the step 6
  lookup. In atx-conformance at af921e5, `revoked` and `revoked-crl-only` are the two fixtures
  whose verifier state carries a revocation list, the fixture schema admits `agentId`,
  `revokedAt` and `reason` in an entry and no other member, and both reference verifiers compare
  an entry's `agentId` with the credential's `agentId`. No BCP 14 statement is added or removed.
  Keying the fixtures' list by `agentDid` belongs in atx-conformance and is not part of this
  change. (#55)
- `.pre-push-review-not-required` says what runs in this repository. It opened "Spec/docs-only
  repository. No CLI, build, test suite, or runnable artifacts." while `scripts/` held 41 tracked
  files: 18 `check_*.py` checks, 19 `test_*.sh` and 2 `test_*.py` tests, `validate_examples.py`
  and `gen_errata_index.py`, of which the workflows run `validate_examples.py`,
  `check_conformance_counts.py`, `check_errata.py` and `test_errata.sh`. It now names each of them
  by a backticked path or glob, says what each kind does and which of them CI runs, and says there
  is no package, CLI tool or build output to install. It points review at pull requests and issues
  on this repository, as `CONTRIBUTING.md` does; it named PR review and issue threads on
  a2aproject/A2A. No normative text changes. (#99)
- `scripts/check_review_marker.py` reads a "no", "without" or "neither" as the opening of a list
  of its own where it stands inside the list of another. Its matches did not overlap, so such a
  negation was read only as words of an item of the outer list. In "There is no package and no
  tests.", "There is no CLI, and there are no tests." and "No build, without tests." no item of
  the outer list begins with a denied term, and, in a tree whose `scripts/` holds two files, each
  exited 0, while "There are no tests." exited 1. Each now exits 1 with `[denied]` for "tests",
  and "There are no runnable files and no executables." reports `[denied]` for "executables" as
  well as for "runnable". The delivered `.pre-push-review-not-required` passes.
  `scripts/test_review_marker.sh` adds 5 cases; run with the check at fa77e5a, 7 of its 40 cases
  fail, and all 40 pass on this tree. (#101)
- The stated conformance-suite count follows the suite to **27** fixtures. atx-conformance added
  `fixtures/v1_1-scan-summary-member-outside-type.json`, a MUST-REJECT v1.1 credential signed
  with `scanSummary.criticalFindings` 0 that carries the JSON string `"3"` in that member,
  written after signing. §1.3a.2 rule 2 brings `criticalFindings` into the TBS as an integer, so
  no signature covers a string there and the credential is rejected as a signature failure; a
  verifier that leaves a member it cannot decode at its zero value projects the signed 0 and
  accepts it. `README.md` carried the verifier's summary line for 26; `docs/conformance.md`
  carried "26 fixtures" and "26 of 26 PASS"; §12 carried "26 fixtures". Each follows the suite,
  and the fixture joins both fixture enumerations. Against atx-conformance at ca1ee3e both
  reference verifiers report `summary: 27 pass, 0 fail (27 fixtures)`. No normative text changes.
- `scripts/test_conformance_counts.sh` also runs the delivered `README.md`, `docs/conformance.md`
  and `core.md` against a real suite checkout when `ATX_CONFORMANCE_SUITE` names one, as
  `scripts/test_coverage_index.sh` and `scripts/test_schema_refusals.sh` do, and skips that case
  otherwise. Against atx-conformance at ca1ee3e the case fails on the documents that stated 26
  fixtures and passes on these.
- `core.md` §1.3a.2 rule 1: a present `behavioralProfile` that is not the canonical
  `{checksum,generatedAt,observationDays}` object is a signature failure (`SIGNATURE_INVALID`), as a
  present-but-outside-type `scanSummary` member is under rule 2. The JSON literal `null` is the
  absent form and any other value is present. A present profile is well formed only as a JSON object
  whose member names are exactly those three, compared exactly, with `checksum` a JSON string,
  `generatedAt` a JSON string in the RFC 3339 `date-time` form decided as `issuedAt` and `expiresAt`
  are, and `observationDays` a JSON number read as an integer as `trustLevel` is. A well-formed
  profile is projected as an object of exactly those three members, with `generatedAt` in UTC to
  whole seconds. A verifier rejects a present profile that is not well formed, and never projects it
  to JSON `null` or coerces an unreadable member to a zero value; the `sha256:` prefix of `checksum`
  and a non-negative `observationDays` bind the issuer (§12) and are not grounds for a verifier to
  reject. Rule 2 states the matching `scanSummary` rule: a `scanSummary` that is not an object, or
  that holds one of its six members outside its type, is a signature failure (`SIGNATURE_INVALID`),
  while an absent or `null` member stays the zero value. §13 cross-references both rules. An absent
  or `null` profile and a well-formed one project to the bytes they projected to before, so no byte
  vector changes. The conformance fixtures for the `behavioralProfile` rule belong in
  atx-conformance and are not part of this change.
- The stated conformance-suite count follows the suite to **26** fixtures. atx-conformance added
  `fixtures/v1_1-declared-purpose-number-injected.json`, a MUST-REJECT v1.1 credential signed
  with no `declaredPurpose` that carries the number 1.5, which is not an integer, as a
  `declaredPurpose` appended after signing. §1.3a.2 rule 5 includes a non-object value in the TBS
  verbatim, so the recomputed canonical bytes no longer match the Ed25519 signature and the
  credential is rejected as a signature failure. `README.md` carried the verifier's summary line
  for 25; `docs/conformance.md` carried "25 fixtures" and "25 of 25 PASS" and named array and
  string values among the injected values rejected; §12 carried "25 fixtures". Each follows the
  suite, and `docs/conformance.md` names number values as well; §12's "injected non-object
  values rejected" already covers the fixture. No normative text changes.
- `scripts/check_schema_refusals.py` reads every name in backticks in a sentence of the `core.md`
  §12 Issuer paragraph that says the schema refuses as a fixture name, apart from `atcVersion` in
  the phrase "Ed25519-only fixtures that declare `atcVersion` 1.1", and fails as `[stale]` when
  the suite ships no fixture of that name. It compared only the names that were suite fixtures, so
  a refusal sentence naming `v1_1-hybrid-pq-only` passed against a suite that does not ship it,
  and a name the suite removed or renamed went unreported. A member name such as `signatures` in
  backticks in such a sentence, outside that phrase, now fails as well.
  `scripts/test_schema_refusals.sh` adds 3 cases.
- `core.md` §12 Issuer says which conformance fixtures the credential schema refuses: the
  Ed25519-only fixtures that declare `atcVersion` 1.1, which lack the ML-DSA-65 signature §1.1
  requires, and `v1_1-hybrid-pq-only`, which lacks the Ed25519 one. It said "Those of them that
  declare `atcVersion` 1.1" after a clause about the fixtures that carry Ed25519 signatures only,
  which reads as every fixture that declares 1.1, while `v1_1-baseline-valid-hybrid` and
  `v1_1-hybrid-mldsa-tampered` declare 1.1, carry both suites and validate, and it did not name
  `v1_1-hybrid-pq-only`. Copied over the suite's vendored schema in atx-conformance at 2ac8f91,
  this schema fails 13 of the suite's 25 fixtures in `scripts/schema_validation.py`
  (`summary: 12 pass, 13 fail (25 fixtures)`): the twelve Ed25519-only fixtures that declare 1.1,
  four of them pinned ACCEPT and eight pinned REJECT, and `v1_1-hybrid-pq-only`, pinned REJECT.
  `docs/conformance.md` said the schema is CI-validated against the suite's fixture set; it now
  says the suite validates its fixtures against a copy it vendors from a pinned revision of this
  repository, and points to §12 for the fixtures the schema refuses. At 2ac8f91 that copy is the
  schema as of e89bed9, which has no two-suite rule. The schema's description of the two-suite
  rule names the ML-DSA-65-only form beside the Ed25519-only one. Moving the suite's vendored copy
  to this schema needs each of those 13 fixtures to carry both suites or the suite's schema check
  to expect its refusal, an atx-conformance change that is not part of this one. No normative
  text changes.
- `scalability.md` §9.2 places the root's cosignature at issuance, as `core.md` §7 and
  `sovereign-federation.md` §3.2 do. It said cross node cosignatures for a partitioned node
  degrade to "unverified by root" until the partition heals, which has the root take a step when
  a credential is verified; it now says the root cosigns at issuance and, while the partition
  lasts, cannot cosign what the node issues, so the node issues nothing at trust level 4 until the
  partition heals. `scripts/check_mediation.py` gains the rule `root-verifies`: a sentence in
  which the root verifies ("verified by the root", "unverified by root", "the root node
  verifies") fails unless a negation stands before it or the sentence says it is at issuance, and
  "verified by the root's key" passes. `scripts/test_mediation.sh` covers the passive, active,
  wrapped and table-row forms that fail and the negated, issuance and root-key sentences that
  pass.
- `scripts/check_pointers.py` checks that the §1.3 step 5 threshold bullet of `core.md` and the
  threshold paragraph of `sovereign-federation.md` §2.3, which say the authority's DID document
  declares the key set, cite §1.3b, where that declaration is defined, and that §1.3b names
  `thresholdKeySets`, `members` and `threshold`; a tree without a §1.3b heading fails as
  `[definition]`. `scripts/test_pointers.sh` adds 7 cases, and the paragraph of its case for a
  reference wrapped across lines now also cites §1.3b. (#74)
- `core.md` section 12, Coverage, names the treatment of `scanSummary.techniques` under the
  signature (§1.3a.2 rule 6) among the requirements no conformance fixture exercises, and its
  self-attestation requirement names §1.3a.2 rule 6, so an implementation self-attests it until a
  fixture exercises it. No BCP 14 statement is added or removed. A fixture that pins the member's
  bytes, and the reference verifiers' handling of the member, belong in atx-conformance and are
  not part of this change. (#55)
- `docs/use-cases.md` says, as `core.md` section 12 does, that a verifier that rejects on the
  `revoked` field and never reads the revocation list still rejects `fixtures/revoked.json`. It
  said a verifier that never reads the list still rejects it, leaving out the field that verifier
  rejects on. (#55)
- `sovereign-federation.md` §7.2 said a verifier reconstructs the inclusion proof of a sovereign
  issued ATX from cached data. The proof's audit path is in none of the ATX, the DID document or
  the STH, so step 3 now says the verifier fetches the proof from the sovereign's transparency log
  by the index the ATX carries and caches it, and that an ATX without `transparencyLogIndex` gives
  it no index to fetch the proof by, so the steps do not establish that ATX's inclusion, and the
  missing index is not evidence that its issuance went unlogged. The section now says the checks
  run without contacting the sovereign and fetching a proof does contact it, and that a more
  recent STH needs a proof of its own from the log. (#55)
- `sovereign-federation.md` §5.2 said a sovereign can mark a credential sovereign only and a
  revocation "details classified". The credential schema has no member for the first, and the
  ATP-SPEC v1.0.0-rc1 §8.1 entry has none for the second: its five members are `agentDid`,
  `revokedAt`, `reason`, `transparencyLogIndex` and `revokedByKeyId`, and it admits no other. The
  table now says a sovereign keeps a classified agent's credential inside its perimeter by not
  presenting it outside, and keeps the details behind a revocation inside its perimeter while it
  publishes the revocation as an §8.1 entry. (#55)
- `scripts/check_revocation_cursor.py` finds each `agentId`, each CRL or revocation list and each
  sentence end or blank line once per file and pairs them in one pass, and finds a failure's line
  by bisecting the file's newline offsets. One regex from `agentId` to the list scanned the rest of
  a sentence again for every `agentId` in it, so a sentence naming `agentId` many times with no
  list after it took time quadratic in its length, 0.37 s at 16 KB and 1.47 s at 32 KB, and
  counting newlines from the start of the file for each failure took 6.45 s for 40,000 failing
  lines. Measured in-process after the change, each doubling of such a sentence from 256 KB to
  4 MB, and of a file of failing lines from 80,000 to 640,000 lines, roughly doubled the time.
  `scripts/test_revocation_cursor.sh` checks that the one pass reports the matches the regex
  reported on 5000 generated texts, and that a 256 KB sentence and a file of 80,000 failing lines
  are each checked within 10 s. (#55)
- `README.md` is shorter. Its Use cases section, renamed What it does, keeps what ATX does in each
  use case, where it stops (one sentence for the second) and the reference verifier's commands;
  each use case in full, with its problem statement and the fixtures it names, is now in
  `docs/use-cases.md`. The Contributing and Conformance sections are rows of the Documentation
  table, formerly Documents, and `CONTRIBUTING.md` and `docs/conformance.md` hold what they said.
- `scripts/check_readme_lead.py` excludes `pre`, `script`, `style` and `textarea` from the
  HTML block kind opened by a line holding only one tag for an open tag only, as CommonMark
  does. It excluded them for a closing tag as well, so a README whose `# ` line stood directly
  under a line holding only `</pre>`, where CommonMark reads both lines as one HTML block and
  renders no heading, passed with a title on line 2; it now fails as `[missing]` at line 1. A
  line holding only `</pre>` directly under a line of text still opens no block.
  `scripts/test_readme_lead.sh` adds 5 cases: `</pre>`, `</SCRIPT>`, `</style >` and
  `</TextArea>` above the title, and `</pre>` under the navigation line. (#89)
- `scripts/check_readme_lead.py` reads HTML blocks as CommonMark does. It took any `# ` line
  outside a fenced code block as the title, so a README whose `# ` line stood directly under
  `<div align="center">`, where CommonMark reads it as part of an HTML block and renders no
  heading, passed with a title. A `# ` or `## ` line inside an HTML block of any of CommonMark's
  seven kinds is now not a heading: a block opened by a `<pre>`, `<script>`, `<style>` or
  `<textarea>` tag, a comment, a processing instruction, a declaration or a CDATA section closes
  on the line holding its end marker, and one opened by a block-level tag or by a line holding
  only one tag closes at the next blank line; a line holding only a tag opens no block directly
  under a line of text. A README with no title outside such blocks fails as `[missing]` at line
  1, and the message now names HTML blocks. `scripts/test_readme_lead.sh` adds 11 cases. (#87)
- `scripts/check_readme_lead.py` reads fenced code blocks as CommonMark does. It flipped its
  fenced state on every line starting with ```` ``` ```` or `~~~` after any indentation, so a
  block holding a `~~~` line, a shorter fence or a fence line with an info string ended there,
  its last fence line opened a new block, and the title below was reported as missing. A fence
  is now three or more backticks or tildes indented at most three spaces, a backtick fence's
  info string holds no backtick, and a block closes only on a fence of the same character, at
  least as long as the opening one, with nothing after it but white space; a line indented four
  or more spaces, or by a tab, neither opens nor closes a block. `scripts/test_readme_lead.sh`
  adds a case for each of those shapes, one for a closing fence longer than the opening one and
  one for fences indented three spaces with a tab after the closing one. (#84)
- `scripts/test_readme_lead.sh`: two cases now use a README whose verdict depends on the rule
  they are named for. In "badge lines and a comment line do not count as paragraphs" the comment
  line stood directly above the description, so read as text it would join the description's
  one-sentence paragraph; it now stands between blank lines, and the same README with a line of
  text in its place fails at line 7. In "a heading inside a fenced code block does not end the
  lead" the fence line below the description was reported as a second paragraph whether or not
  the fence was honoured; the block now stands above the description, which is reported as the
  second paragraph at line 7, and the same README with its fence markers replaced by text
  passes. The change did not alter the number of cases. (#81)
- `scalability.md` §2.1 describes the expiry check as two comparisons against the verifier's
  clock. Its notes cell said "Single comparison", while `core.md` §1.3 step 2 compares that clock
  with the earlier of `expiresAt` and `issuedAt` plus the seven-day credential TTL, and with
  `issuedAt`. The row now names both bounds and links §1.3; its cost of 0.001 ms is unchanged.
  (#76)
- `core.md` §3.2 step 2 checks the validity window of §1.3 step 2. It said "Check expiresAt is in
  the future", which passes a credential whose `issuedAt` is in the future, or whose `expiresAt`
  lies past `issuedAt` plus the seven-day credential TTL, while that `expiresAt` is still ahead.
  It now says the ATX is expired at the earlier of `expiresAt` and `issuedAt` plus that TTL and
  is not yet valid while `issuedAt` is in the future, both within the family clock-skew bound of
  ATP §10.2, as §1.3 step 2 does. (#69)
- `core.md` §3.1 step 8 and `sovereign-federation.md` §2.3 state the threshold rule as §1.3 step
  5 does: once a signature under one of the set's keys verifies, a verifier rejects the
  credential unless signatures under at least the threshold number of distinct keys of the set
  verify. They said a verifier rejects a credential that carries verifying signatures from fewer
  of those keys than the threshold, which also covers a credential that carries none of the
  set's signatures, and step 5 does not reject that one. No verification rule changes.
- `core.md` §4.2 item 4 and the HSM item of `sovereign-federation.md` §2.2 name §1.3 step 5, and
  `scripts/check_pointers.py` checks both. Its description named "every section that describes
  threshold signing" while it checked three places; it now names the five it checks, and says
  that other mentions, such as the §1.2 lifecycle table, are not checked.
- `scripts/check_pointers.py` passes a sentence naming the forge lab only when the lab is the
  subject of "signs" or "signed": "the lab", "the forge lab", a Markdown link to the lab, or "it"
  stands directly before the verb. "The forge lab checks what you signed and rejects anything
  that is not an ATX credential" and "The forge lab, a sign of progress, rejects anything that is
  not an ATX credential" fail; both passed.
- `scripts/check_mediation.py`, `scripts/check_revocation_list.py`, `scripts/check_pointers.py`
  and `scripts/check_conformance_counts.py` find each failure's line by bisecting the newline
  offsets of its file, or of its paragraph in `check_pointers.py`, found once, instead of counting
  newlines from the start for each failure. On a 1.6 MB file of repeated failing text the four
  took 8.8, 16.5, 11.2 and 29.6 seconds and now take under 0.4 seconds each; on
  scratch trees compared with the previous scripts the output is the same. Each check's test
  script adds a file of repeated failing text, expects it checked within 10 seconds, and checks
  the line reported for its last failure.
- `core.md` §12 gains an informative paragraph, "Verifier clock", after the conformance suite
  paragraph. Each fixture carries the verifier's current time in `verifierState.clockRfc3339`,
  and a verifier under test takes "now" from that member, as both reference verifiers do. Every
  current fixture pins `2026-05-24T00:00:00Z`, one day after the `issuedAt` of each fixture that
  pins ACCEPT, so §1.3 step 2, its seven-day bound included, rejects none of them, and a verifier
  that implements all of step 2 produces every pinned verdict. A verifier that substitutes its
  own wall clock finds those fixtures expired once seven days have passed since their
  `issuedAt`, which is a difference of clock, not a conflict between step 2 and the suite. No
  normative text changes. (#70)
- `sovereign-federation.md` §3.2 places cosigning at issuance, as `core.md` §7 does. It said
  "Cosignature path established" for an allowed issuer; verification now proceeds locally over
  the signatures the credential already carries, including any cosignature, which was made at
  issuance.
- `scripts/check_conformance_counts.py` reads a count with `byte-pinned`, `pinned`, `shipped` or
  `conformance` between the number and "fixtures", and it reads the pass count of a
  `N pass, 0 fail` summary line, so the pass count in the reference verifier's summary line in
  `README.md` is checked as well as its fixture count. A count with any other word there, such as
  "3 hybrid fixtures", counts a subset and is not compared with the suite.
- `scripts/check_mediation.py` no longer passes a sentence because it names issuance. A request
  is made at issuance when the sentence says so ("at issuance") or the actor named last before
  the verb is the issuing side, so "the verifier queries the issuing node for a cosignature"
  fails. A negation counts only when it stands before the verb past auxiliaries, adverbs and
  catenatives ("does not fall back to asking"), so "if X is not listed, the verifier queries the
  root node" fails. An `issuerChain` list with no closing bracket and a long run of negated verbs
  are checked in linear time; both took time quadratic in their length.
- `scripts/check_pointers.py` passes a sentence naming the forge lab only when it says the lab
  signs something before it says "not an ATX credential", so "rejects anything that is not an ATX
  credential" fails. `README.md` now says the lab signs the simplified object whose expiry it lets
  you pass.
- `scripts/check_revocation_list.py` names ATP-SPEC v1.0.0-rc1 section 8.1 in every message, since
  the example entry the 227 bytes come from is 212 bytes in the later 1.1.0 draft. A number starts
  only where a run of digits and commas starts, and each count of revocations takes the first size
  after it from one scan of its sentence, so long digit runs and many counts in one sentence are
  checked in linear time; they took time quadratic in their length.
- `scripts/test_schema.py` pins that an `atcVersion` 1.0 credential with one signature suite is
  accepted and a 1.1 one refused, and checks the JSON Patch `test` and `remove` operations that
  `scripts/validate_examples.py` applies to build the `mustReject` variants. `scripts/test_pointers.sh`
  covers the hidden-directory skip, `scripts/test_revocation_list.sh` the table-row and list-item
  paragraph split, and both they and `scripts/test_mediation.sh` cover the cases above, large
  inputs included.
- `README.md` is shorter and opens with a link to `core.md` section 1.3, the algorithm every
  verifier runs. Its reference text moved, as written, to three new pages it links:
  `docs/status.md` takes the Status section (document version, wire format, which service
  issues and which verifies ATX, the ATP and AIP specifications); `docs/conformance.md` takes
  the conformance-suite paragraph with its fixture list and verifier counts; and
  `docs/use-cases.md` takes the sentence comparing `fixtures/revoked.json` with
  `fixtures/revoked-crl-only.json`. The README keeps the fixture count only in the reference
  verifier's summary line, and `scripts/check_conformance_counts.py` now also checks the counts
  in `docs/conformance.md`.
- `README.md` holds only its description between the title and the first section. The
  paragraph that followed it (what an ATX is, the TLS certificate comparison, the local
  verification bound and the two signature suites) moved, as written, to `docs/use-cases.md`
  under "What ATX is". The first use case now states its verification bound as "under 5 ms on a
  warm cache", the condition `core.md` §1.3 gives for it, so `README.md` still states the warm
  cache total that `scripts/check_latency.py` requires of it.
- `scripts/check_conformance_counts.py` reads the fail count of the reference verifier's summary
  line in `README.md` (`summary: 25 pass, 0 fail (25 fixtures)`) as well as its pass and fixture
  counts: a fail count other than 0 exits 1 naming the file and line, since a run that passes
  every fixture reports no failures. Before, a README stating `25 pass, 1 fail (25 fixtures)`
  passed against a 25-fixture suite. `scripts/test_conformance_counts.sh` covers a summary line
  stating a failure, one moving a fixture from pass to fail, and a fail count in
  `docs/conformance.md`.
- The stated conformance-suite count follows the suite to **25** fixtures. atx-conformance added
  `fixtures/revoked-crl-only.json`, a MUST-REJECT v1.0 credential whose own `revoked` flag is
  false and whose agent is on the verifier's revocation list, so the §1.3 step 6 list check now
  has a fixture of its own and a verifier that never reads the list fails it, and
  `fixtures/v1_1-hybrid-pq-only.json`, a MUST-REJECT v1.1 credential carrying one ML-DSA-65
  signature that verifies and no Ed25519 signature, which §13 rejects. `README.md` carried
  "23 fixtures", "23 of 23 PASS", the verifier's summary line for 23 and, in its "Why you can
  check this yourself" paragraph, "ships 23 byte-pinned fixtures", and said no fixture yet
  rejects an agent on list membership alone; §12 carried "23 fixtures", said step 6 has no
  fixture of its own, and in its Issuer paragraph said all but the three hybrid fixtures carry
  Ed25519 signatures only, where four fixtures now carry an ML-DSA-65 signature, one of them
  with no Ed25519 signature. All of those follow the suite, and both fixtures join both fixture
  enumerations. No normative text changes.
- `core.md` §1.3 step 2: an ATX is expired at the earlier of `expiresAt` and `issuedAt` plus the
  seven-day credential TTL of §1.2, and is not yet valid while `issuedAt` is in the future; §12
  adds the matching issuer duty and lists both checks among the requirements no conformance
  fixture exercises yet. (#48)

- `scalability.md` §6.2 and §6.3 describe the revocation list ATP-SPEC v1.0.0-rc1 §8.1 defines.
  §6.3 said the cached CRL is signed so that a stale one cannot be tampered with, but the §8.1
  response has no member for a signature and allows no additional members, and `core.md` §2
  item 5 says it is not signed in ATP 1.0. §6.3 now says its authenticity rides on the transport
  and on each entry's `transparencyLogIndex`, that a server on the path can drop an entry without
  the list showing it, and that a signed revocation list is ATP 1.1 work. §6.2 put each entry at
  roughly 40 bytes and a million revocations at 40 MB; each entry has five required members, the
  §8.1 example entry is 227 bytes as compact JSON, and §6.2 now says roughly 227 bytes per entry
  and about 227 MB per million revocations before compression. No normative text changes.

- Section 1.3a.2 rule 6 says that an issuer MUST NOT list the same technique ID twice in
  `scanSummary.techniques`. The schema's `uniqueItems` and `scripts/test_schema.sh` already
  rejected a repeated ID, but rule 6 said only that each item is a `T-NNNN` string and that a
  verifier does not deduplicate, which read as if a repeated ID could be valid. A verifier still
  signs a present value verbatim, including one that repeats an ID. This adds one BCP 14
  statement. The schema's `transparencyLogIndex` description no longer says the field is omitted
  when the issuer recorded no inclusion, the reading section 1.1 dropped; it says, as section 1.1
  does, that omitting the field does not exempt the issuance from being logged before it takes
  effect.
- `scripts/test_schema.py` writes no `scripts/__pycache__/` when it imports
  `validate_examples`, so running it leaves the working tree clean, and `scripts/test_schema.sh`
  asserts that in a scratch copy.
- Links to the ATP and AIP specifications and to the conformance suite's `jcs-vectors/` in
  `README.md` and `core.md` sections 1.3a.3 and 10 name `opena2a-standards`, where those
  repositories now live, instead of `opena2a-org`, which answers 301. The `core.md` header link to
  ATP-SPEC v1.0.0-rc1 points at `ATP-SPEC.md` at the `v1.0.0-rc1` tag; the repository root shows
  the next draft. Section 3.2 step 2 checks `atcVersion`, the wire member, where it said
  `atxVersion`, which the schema rejects. The `README.md` scope cell for `scalability.md` says it
  covers transparency log scaling and monitor cost and names `core.md` §6.4 for the monitor
  verification cycle. No BCP 14 statement is added or removed.
- `core.md` section 8, the product integration map, no longer states HackMyAgent's check counts
  or the number of factors in AIM's trust score. It said 209 static checks and an 8 factor trust
  score; the HackMyAgent README states 317 static checks and AIP §6.1 specifies a 9-factor
  algorithm. The HackMyAgent row now links the README for the counts and the AIM row links AIP
  §6.1, so the map cannot fall behind either source again. The section is informative and no
  normative text changes.
- `scalability.md` states figures that follow from the inputs it gives. Verifications per core
  are about 277, not 1,000: the §2.1 steps sum to 3.611 ms, so a four-core verifier handles
  about 1,100 a second and a billion a second needs about 900,000 verifiers, not 250,000. The
  §2.1 warm cache total is 3.5 to 3.6 ms, the sum of its steps, where it said 1 to 4 ms, and the
  ML-DSA-65 step is required rather than optional, since every credential carries that
  signature (`core.md` §1.1). A credential is about 6 KB, not 1 to 4 KB averaging 2 KB: the
  base64 ML-DSA-65 signature alone is 4,412 characters. The active set is therefore 6 TB for a
  billion credentials and 600 MB for a 100,000 agent node, where it said 2 TB and 200 MB. A month
  of log entries at 1,650 a second and 256 bytes is about 1.1 TB, not 4 TB, and the 100,000
  agent node's yearly log mirror is about 1.3 GB, not 10 GB. The node's reissuance is about
  1 KB a second on average and about 60 KB a second at the 10 issuances a second §10 suggests
  for that population, where it said 150 KB a second with no rate to derive it from. §10 says
  its capacity table is sizing guidance and not a conformance criterion, where it called the
  figures the minimum capacities for ATP conformance: the conformance targets of `core.md` §12
  state no capacity. The §1 summary says a 10 million entry log verifies in 24 hashes, where it
  said 23: an RFC 6962 inclusion proof in a log of that size is at most 24 hashes, the base 2
  logarithm of the entry count rounded up, as the §5.1 table counts it. §1 also names the
  figures that are computed from the populations, rates, sizes and step costs the document
  states, where it called the numbers direct consequences of the architectural commitments in
  the core doc. No BCP 14 statement is added or removed.
- `core.md` no longer cites an ATP version negotiation or an ATP working group draft, neither of
  which exists. Section 10 and the signature suite row of the section 14 registry table said
  additional suites are added via ATP version negotiation; ATP-SPEC v1.0.0-rc1 defines no
  negotiation, so both now state the change policy as it is, specification revision. Section 2
  said ATP is pushed into the IETF as a Working Group draft; no ATP Internet-Draft exists, and a
  working group draft is one a working group has adopted, so section 2 now describes the IETF
  work as intended: an individual Internet-Draft, as AIP and AAP already have, and then a request
  to a working group to adopt it. A version negotiation, if one is added, is specified in ATP. No
  BCP 14 statement is added or removed.
- §12 Coverage names the k-of-n threshold issuance of §3.1 step 8 (cosignatures from 2 of 3 key
  holders) among the requirements no fixture exercises, and adds §3.1 step 8 to the requirements
  an implementation self-attests. The atx-conformance `notCovered` list cites §3.1 step 8 and the
  paragraph did not, which the family spec-drift check `notcovered-index-agrees-with-spec`
  reported. The threshold cosignature fixture pins a credential carrying all three signatures,
  and the fixture format has no field for the number the threshold requires, so a verifier that
  never counts signatures against a threshold, or checks only the first, passes it. No verdict
  on any fixture changes.

- `scalability.md` and `sovereign-federation.md` no longer have a verifier lower a signed trust
  level or describe capabilities as authorization, which contradicted `core.md` sections 1.3 and
  1.5. `scalability.md` §9.2 said trust level 4 requests fall back to trust level 3 during a
  partition; it now says the node issues nothing at trust level 4 while the root cannot cosign
  (core.md §7 rule 4), that a request requiring trust level 4 is not met by a credential issued
  in that time, and that a credential the root cosigned earlier keeps its signed level.
  `sovereign-federation.md` §3.1, §4.1 step 5 and §4.4 said the trust level of a credential from
  a Conditional authority is capped; they now say the verifier reports the sovereign's ceiling as
  its own marker beside the signed level, which stays as signed, and that policy acts on the
  lower of the two. Section 4.4 is retitled from "Trust level downgrade across borders" to "Trust
  level ceilings across borders", so its anchor changes. Section 4.4 also said the credential
  authorizes capabilities, and the §8.1 human oversight row said the ATX shows human authorized
  capabilities; both now say `capabilities` are what the build is attested to be able to do, not
  permission, and that whether an agent may act is a broker policy decision under AAP. No BCP 14
  statement is added or removed.
- `docs/conformance.md` no longer describes the conformance suite's threshold fixture as a 2-of-3
  threshold cosignature. The fixture carries three signatures from one authority's threshold key
  set and every one of them verifies, so it pins that each declared signature verifies and not
  the threshold of `core.md` §1.3 step 5. §12 Coverage names that threshold among the
  requirements no fixture exercises, beside the threshold issuance of §3.1 step 8, and corrects
  two statements about the suite. The fixtures do not all assert `trustLevel` 4: every one but
  `wrong-issuer`, which asserts 1, does. The `conformance.json` profile does name the requirement
  each fixture exercises, in each entry's `requirement` member, and its entries do not all cite
  the same specification sections: they draw their `specRefs` from a few lists that several
  entries share, so an entry's `specRefs` name an area of `core.md`, not the requirement its
  fixture pins.
- `schemas/atx-credential-v1.1.schema.json` follows `core.md` in five places where the two
  disagreed. `taskScopes` tokens and the values of `capabilityJustification` follow the §1.5.2
  grammar `^[a-z][a-z0-9]*:[a-z][a-z0-9_]*$`; the schema allowed hyphens, underscores and a
  leading digit in the namespace, and uppercase letters, dots and hyphens in the objective, and
  checked no grammar on `capabilityJustification` at all. `capabilities` tokens and the
  keys of `capabilityJustification` follow the AIP §4.1 grammar that §14 cites, which admits the
  organization-prefixed form (`acme.example/billing:refund`) and no wildcard action; the schema
  rejected the first and accepted `db:Read.*`. `declaredPurpose: null` validates, since §1.3a.2
  rule 5 treats it as absent, as it does the empty object. `publisherDid`, `buildAttestation` and
  `scanSummary.oasbLevel` accept the empty string that §1.3a.2 rules 1 and 2 name as their value
  when unknown, so a credential with an unknown value has a valid wire form. The
  `capabilityJustification` description no longer says a verifier enforces its subset rule:
  neither reference verifier reads the member, and the subset relation is a cross-field rule the
  schema cannot express. Every atx-conformance fixture validates as it did before; the suite's
  vendored schema copy moves in its own atx-conformance change, as does a fixture and a verifier
  check for the subset rule. No normative text changes.
- `scalability.md` and `sovereign-federation.md` drop the members and mechanisms below, which
  neither the schema nor `core.md` defines. `scalability.md` §9.1 said the build plugin mints ATX
  during an issuing-node outage under a 30 day delegated signing certificate; core.md defines no
  delegated signing, so builds now queue and are issued when the node recovers. §9.3 said ATX
  issued while the log is down are marked "log pending", and that a missing log index is
  detectable; the credential has no such mark and the index is optional, so issuance pauses until
  the log accepts entries (core.md §11 commitment 3) and logging is established by the log's
  inclusion proof. `sovereign-federation.md` §7.2 said the ATX includes the Signed Tree Head that
  contains its log entry; it carries no STH, only the optional index. Section 1.1 no longer says
  an issuer that recorded no inclusion omits `transparencyLogIndex`, which read as permitting
  issuance without logging: omitting the field does not exempt the issuance from being logged
  before it takes effect. No BCP 14 statement is added or removed by these corrections.
- Section 1.3 step 6 and section 3.2 step 6 check `agentDid` against the cached revocation list,
  the key each ATP-SPEC v1.0.0-rc1 §8.1 entry carries. Both said `agentId`, which no entry in
  that list has. Section 1.3 step 6 also says the issuance envelope's `revoked` field is outside
  the signed bytes and does not stand in for the list check. Section 12, Coverage, and the
  `README.md` revocation use case say that no conformance fixture yet rejects an agent on list
  membership alone: the revocation fixture also carries `revoked: true`, so a verifier that never
  reads the list still rejects it. No BCP 14 statement changes.
- A verifier that does not list a credential's issuer rejects it as an untrusted issuer, and
  asks nobody for a cosignature. `core.md` §7 step 3 and `sovereign-federation.md` §3.2 and §4.2
  had the verifier query the root node for one, which contradicted `README.md`, `core.md` §9 and
  §11 commitment 6 (verification never makes a network call to a node) and the reference
  verifiers, which reject an unlisted issuer and make no call. The mediated path in
  `sovereign-federation.md` §4.2 now runs ahead of verification: a sovereign that wants to honor
  the authorities the root recognizes imports the root's published trust list into its own, and
  an authority it lists as Denied stays denied. A root cosignature, which trust level 4 requires,
  is made at issuance over the same canonical bytes as the first signature. The old text gave
  the cosigned credential `issuerChain` = [gov.x, opena2a.org]; under `atcVersion` 1.1 the chain
  is inside the signed bytes, so extending it after the first signature invalidated that
  signature, and it put the root last where §1.3a.2 rule 4 puts it first. The chain is now
  settled, root first, before anyone signs. `scalability.md` §7 bounds the root's load by the rate
  of issuance that needs its cosignature, not by a share of verifications. No BCP 14 statement is
  added or removed.
- `schemas/atx-credential-v1.1.schema.json` refuses an `atcVersion` 1.1 credential whose
  `signatures` array lacks an Ed25519 or an ML-DSA-65 entry, as §1.1 requires. `signatures` sits
  outside the signed bytes, so anyone relaying a credential could delete the post-quantum entry,
  or the Ed25519 one, and the schema still accepted the result. `atcVersion` 1.0 is frozen legacy
  and is not constrained. `scripts/validate_examples.py` applies an entry's `mustReject` variants,
  JSON Patch (RFC 6902) `test` and `remove` edits of the mapped example, and fails unless the
  schema refuses each one; `schemas/examples-map.json` deletes each suite from the §1.1 example in
  turn. The sentences that called the post-quantum suite optional now match §1.1: the section 0
  comparison table names Ed25519 and ML-DSA-65 libraries where it said any Ed25519 library,
  section 3.2 step 5 verifies the ML-DSA-65 signature where it verified one only if present, and
  the `scalability.md` §2.1 breakdown calls that verification required where it said optional
  path. Section 12 states that the conformance fixtures declaring `atcVersion` 1.1 with Ed25519
  signatures only fail the schema. A reference-verifier rule that rejects such a credential, and
  hybrid fixtures that pin it, are atx-conformance changes and are not part of this one. No BCP 14
  statement is added or removed.
- `README.md` no longer says the forge lab at specs.opena2a.org/lab/forge runs the same checks
  as the conformance suite. The lab signs a simplified object of its own, not `JCS(TBS)` as
  `core.md` §1.3a.2 defines it: it names its version member `atxVersion` rather than
  `atcVersion`, gives it the value `1.0` while signing members a 1.0 credential does not sign,
  and does not validate against `schemas/atx-credential-v1.1.schema.json`. The third use case's
  list of ways to check the claims yourself drops the lab, and the two use cases that still link
  it say that what it signs is not an ATX credential, so its verdicts are not conformance results.

- Section 1.3 and section 3.2 step 8 state the verification totals the rest of the repository
  states: under 5 ms on a warm cache, including the ML-DSA-65 verification that the family
  signature gate requires of a hybrid credential, and under 50 ms on a cold cache, which adds one
  DID document fetch. Both said under 2 ms warm and under 10 ms cold, which contradicted the
  section 3 plane table and `README.md` (under 5 ms) and `scalability.md` §2.1, whose step by step
  breakdown puts the ML-DSA-65 verification alone at 3 ms and a cold start under 50 ms. Section
  1.3 step 5 says ML-DSA-65 adds about three milliseconds, as §2.1 does, rather than three to
  five, which a 5 ms total could not hold, and section 3.2 step 5 says about 3 ms where it said
  under 5 ms, a bound that left nothing of the total for the other steps. Section 3.2 step 8 also
  says the issuing node is not queried in either case, as the plane table does. No normative
  text changes.
- Sections 1.5 and 10 name the same authorization layer as `README.md`: whether an agent may
  touch a given resource is a broker policy decision under AAP, and the broker can take the
  credential's verified `capabilities` as one input (§1.3a.4). Section 10 previously gave that
  role to a layer named nowhere else in this repository, and section 1.5 said capability scope
  decides whether an action is permitted, while `README.md` says capabilities are not permission.
  Section 1.5 now says `capabilities` describes which operations the build is attested to be able
  to perform, and its question for an offline observer asks whether an attested operation, not a
  permitted action, serves the declared objective. No normative text changes.
- Section 3.3, the revocation flow, says where the revocation list format is specified: ATP-SPEC
  v1.0.0-rc1 §8.1, with the schema `$id`
  `https://specs.opena2a.org/schemas/atp/revocation-list-v1.schema.json`. It also states that
  the section describes propagation and does not define the format. Section 2 item 5 names
  the same `$id` for the schema it already cited. Before this change, a reader of section 3.3
  alone could conclude the format was unspecified. No format or signature change.
- Section 3.3, revocation step 2, now says the issuing node advances the `nextSince` cursor that
  the ATP-SPEC v1.0.0-rc1 §8.1 revocation response returns. It previously had the node increment
  a version number for the revocation list, which a conforming implementation cannot carry: the
  §8.1 response holds only `revocations` and `nextSince`, and both levels set
  `additionalProperties: false`. ATP §8.1 stays the normative definition of the response. No
  normative text changes.
- The name OpenA2A AIM (Agent Identity Management) is written in full where `README.md`,
  `CONTRIBUTING.md`, `core.md` and `sovereign-federation.md` first use it in running text. `core.md`
  gains an informative paragraph at the end of "Conventions and terminology" that says what AIM is
  and that the document calls it AIM. No normative text changes.
- `README.md`'s navigation bar links AIM under its full name, because that link is the first
  place the file uses AIM. `core.md` sections 3 and 8 and `scalability.md` section 11 name the
  threat intelligence component by what it does, OpenA2A threat research, rather than by an
  internal project name. No normative text changes.
- `README.md` and `CONTRIBUTING.md` say who issues ATX and who verifies it: OpenA2A's issuing node
  is the OpenA2A Registry service, and AIM verifies ATX and does not issue it. Both files previously
  named AIM as a reference implementation. `CONTRIBUTING.md` also names the TypeScript verifier
  package, `@opena2a/atx-verify`. No normative text changes.
- `README.md` no longer says second-party implementations are tracked on a2aproject/A2A#1876, which
  is closed. It asks implementers to open an issue on this repository instead.
- The stated conformance-suite count follows the suite to **23** fixtures. atx-conformance added
  `fixtures/v1_1-no-transparency-log-index.json`, a MUST-PASS credential omitting the optional
  `transparencyLogIndex`. Every other fixture carries the field, so until now nothing in the suite
  exercised its optionality and a verifier that still required it passed the suite unchanged. The
  field is assigned by the log after signing and sits outside both signing forms, so the
  credential's canonical bytes and its signature are identical to the v1.1 baseline's. Section 12's
  fixture enumeration names it; no normative text changes.
- Section 14's transparency-log entry-type row cites its home instead of restating it: the entry
  types are registered in ATP section 5.1.1 (`registries/transparency-entry-types.json`), and ATX
  logs its issuance, revocation and attestation entries under those types. The row previously
  named its own three types, which are not the names the ATP registry uses. No governed set
  changes; this corrects where the set is defined.
- Section 14's capability-token row cites its home instead of restating it: the grammar is
  `namespace:action` per AIP section 4.1, and namespaces are reserved in AIP section 4.2. The row
  previously used a different second term for the grammar and named a product repository as the
  registry's home rather than the specification that governs it. No governed set changes; this
  corrects where the set is defined and what it is called. (The superseded wording is deliberately
  not quoted here: the family drift check counts those literals across every `*.md` in this
  repository, so restating them in a changelog would keep the check red.)

- The stated conformance-suite counts and the reference-verifier capability claims follow the
  suite: it ships **22** fixtures, not 21, and both reference verifiers now verify both declared
  signature suites. atx-conformance added `fixtures/v1_1-hybrid-mldsa-tampered.json` (a hybrid
  credential with the Ed25519 entry intact and one bit of the ML-DSA-65 signature flipped, which
  the §13 family signature gate rejects) and implemented ML-DSA-65 verification in the Python
  reference verifier via `dilithium-py` (FIPS 204). README.md and §12 carried "21 fixtures",
  "21 of 21 PASS", "Python (Ed25519 only; post-quantum verification out of scope for the Python
  stdlib stack)" and "all but the two hybrid fixtures"; all four are corrected, and the new
  fixture joins both fixture enumerations. The count half is what `conformance counts` enforces;
  the verifier-capability half is not machine-checked here, which is why it drifted.
- §13 Cryptographic agility adopts the family signature gate of AAP §9.4: every declared
  signature entry MUST verify, a verifier MUST NOT accept a credential on a subset of its
  declared signatures, and a verifier that does not implement a declared suite MUST reject
  rather than accept on the suites it does implement (AAP §8.2). §1.3 step 5 applies the same
  gate to every remaining declared signature, the ML-DSA-65 entry included. The previous
  sentence permitted classical-only acceptance with a labeling rule; under it the suite's
  Python reference verifier, which records an ML-DSA-65 entry as present without verifying
  it, accepts a credential whose ML-DSA-65 signature does not verify. A MUST-REJECT hybrid
  fixture and ML-DSA-65 verification in the Python reference are a separate atx-conformance
  change and are not part of this one. §12 discloses that all but the three hybrid fixtures
  carry Ed25519 signatures only.
- §1.3 step 2 evaluates `expiresAt` within the family clock-skew bound of ATP §10.2 (cited, not
  restated), which never extends the credential TTL or the revocation cache window.
- `transparencyLogIndex` is optional: removed from `required` in
  `schemas/atx-credential-v1.1.schema.json`. It is the log-assigned index of the credential's
  issuance entry, set after signing and outside both signing forms, so no verdict changes; §1.1
  now binds issuers to emit only the log-assigned value (omitting it when no inclusion was
  recorded) and verifiers MUST NOT read it as evidence of inclusion. The schema and §1.3a.2 text
  calling it a dead field is corrected; the conformance suite's vendored schema copy moves in its
  own atx-conformance change.
- §1.5.4 example capability `secrets:*` becomes `secrets:read`: AIP §4.1 expresses
  capabilities as `namespace:action` strings and lists no wildcard action; AIP #25 adds the
  grammar that states this and adds the `secrets` namespace to the AIP §4.2 registry.
- §12 Coverage self-attestation cites §3.3 and §6.4 rather than whole sections §3 and §6,
  matching the gap list in the same paragraph.
- Three HTML-comment anchors for the OpenA2A spec-family drift checks
  (opena2a-standards/.github#5) added under §1.3, §1.3a.2 and §12 (`opena2a-definition`:
  `atx-verification-steps`, `atx-tbs-exclusions`, `atx-conformance-coverage`); they render
  nothing and change no text.
- core.md §2 item 5 previously promised signed CRL endpoints, delta CRLs and a push
  notification format; it now states what ATP-SPEC v1.0.0-rc1 §8.1 actually defines — the
  since-timestamp revocation response, its schema and the client refresh cadence — with the
  §8.1 revocation response body left unsigned in ATP 1.0 and a signed revocation list named
  as ATP 1.1 work.

### Removed

- `coordination/a2a-sibling-issue-draft.md`, a draft of the coordination issue filed on the A2A
  project as a2aproject/A2A#1885, which is closed.

## [1.1.0] - 2026-07-03

### Added

- `core.md`: qualified document version/status header (credential format v1.1
  normative and shipped; ATP wire detail normative in ATP-SPEC v1.0.0-rc1;
  explicit note that this document never upgrades the maturity of the AIP/AAP
  layers beneath it).
- `core.md`: BCP 14 (RFC 2119 / RFC 8174) conventions section anchoring the
  MUST/SHOULD/MAY language that §1.3a and §1.5 already used.
- `core.md` §12 Conformance: three conformance targets (credential, issuer,
  verifier) and the normative link to the `atx-conformance` suite (15 byte-pinned
  fixtures, `jcs-vectors` cross-language byte-agreement gate, machine-readable
  `conformance.json` profile).
- `core.md` §13 Security considerations: consolidated threat analysis with
  agent-threat-matrix technique IDs (forgeable v1.0 fields / T-4001, bearer
  replay / T-5004, build-tooling compromise / T-9006 + T-9003, DID key
  substitution / T-4007, chain abuse / T-4004, revocation staleness, purpose-as-
  alibi, version downgrade, cryptographic agility).
- `core.md` §14 Registry considerations: IANA-style governance table for ATX
  version numbers, signature suites, DID type prefixes, purpose vocabularies,
  taskScope namespaces, capability tokens, and transparency-log entry types.
- This changelog.

### Changed

- `README.md`: status now names ATX 1.1 as the normative wire format in
  production issuance; conformance section updated from the stale 8-fixture
  description to the current 15-fixture suite with the `v1_1-*` family and the
  `jcs-vectors` gate.

The `v1.1.0` tag, on commit `b2775b4` of 2026-09-08, also carries these changes, made after the 2026-07-03 text described above:

#### Changed

- §12 and README conformance-suite counts synced to the 21-fixture suite: atx-conformance
  #22 added `v1_1-untrusted-chain-authority.json`, the MUST-REJECT fixture for the §1.3 step 4
  key-eligibility sentence (#19), and both fixture descriptions here now name it.

- §12 and README conformance-suite counts corrected to the 20-fixture suite, and
  their fixture descriptions extended to name the strict-parse family that was
  never documented here: duplicate object members rejected at any depth
  (RFC 8259 §4) and case-variant members that a last-wins JSON decoder would
  collapse rejected as `PARSE_ERROR`. Those two fixtures landed in
  atx-conformance on 2026-07-05 and 2026-07-06, after the previous sync to 18,
  so both the count and the description had been understating the suite.
- `scripts/check_conformance_counts.py` + `.github/workflows/conformance-counts.yml`:
  the stated counts are now recomputed from a checkout of atx-conformance@main
  on every push and pull request instead of being maintained by hand. The suite
  is not pinned, because the drift being caught is precisely "the suite moved and
  this repository did not". The guard also fails when a document states no count
  at all, so it cannot pass vacuously.

- §12 and README conformance-suite counts synced to the 18-fixture suite
  (atx-conformance#14 added the three rule-5 degenerate declaredPurpose
  fixtures).

- §1.3a.2 rule 5 pins the degenerate `declaredPurpose` inputs the reference
  verifiers disagreed on (atx-conformance#11): emptiness is a JSON-parse-level
  property (whitespace variants of `{}` are the empty object), and any other
  present value — including non-object values — MUST enter the TBS verbatim,
  so unsigned injected purpose content breaks the signature instead of being
  silently normalized away.
- `schemas/atx-credential-v1.1.schema.json`: `declaredPurpose` now also
  accepts the empty object (wire-tolerated, treated as absent), matching
  rule 5.

#### Added

- `schemas/atx-credential-v1.1.schema.json`: machine-readable JSON Schema
  (draft 2020-12) for the ATX credential wire form, derived from §1.1/§1.3a/§1.5
  with the atx-conformance fixtures as ground truth. All 15 fixtures validate as
  intended (14 shape-valid; `malformed-schema` fails on exactly the `atcVersion`
  registry enum).
- `scripts/validate_examples.py` + `schemas/examples-map.json` + CI workflow:
  every schema is metaschema-checked and the §1.1 example is validated against
  the schema on every push and PR.

#### Changed

- `core.md` §1.1: the credential illustration is now wire-shape-accurate and
  schema-valid — field name `atcVersion` (previously shown under the `atxVersion`
  alias), bare-hex `contentHash`, provenance-URI `buildAttestation`,
  `scanSummary` with `highFindings` and the wire spellings `cryptoServe` /
  `no-weak-crypto`, `trustScore` on the wire's 0-100 scale, full-DID `keyId`
  values, and the issuance envelope fields `id` / `revoked` / `createdAt`.
- `core.md` §2 and §14: the `did:opena2a` type-prefix set now matches the
  did-method registry — `registry` added; `a2a_agent` documented as a deprecated
  legacy alias of `agent`, not a registered type.

## [1.0.2] - 2026-06-08

### Added

- `core.md` §1.5: optional `declaredPurpose` field for ATX 1.1 — publisher-signed
  declaration of agent objective (statement, category, taskScopes,
  capabilityJustification, autonomy, dataScopes, egressScopes), governed
  vocabularies, measured breadth, and verifier guidance (never an authorization
  input, never buys trust). (#5)
- OpenA2A specs family header linking sibling specs and specs.opena2a.org.

### Changed

- `coordination/a2a-sibling-issue-draft.md` refreshed for the post-AIM-PR-#215
  shipped state. (#3)

## [1.0.1] - 2026-06-01

### Added

- `core.md` §1.3a: ATX v1.1 JCS (RFC 8785) canonical signing form — explicit TBS
  projection, determinism rules, frozen v1.0 legacy form, cross-implementation
  byte-agreement mandate, authorization-requires-v1.1 rule, and the version
  transition/downgrade-resistance rule. (#4)

## [1.0.0] - 2026-05-23

### Added

- Initial import of the ATX architecture documents (`core.md`, `scalability.md`,
  `sovereign-federation.md`) from the aim-roadmap tree, superseding ATC
  architecture v2.0 (March 2026).
- DID method unified to `did:opena2a`; AIM identity cross-linked to AIP.
- README cross-link to the `atx-conformance` suite. (#2)
