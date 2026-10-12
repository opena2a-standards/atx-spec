# Changelog

All notable changes to the ATX architecture specifications are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Document
versions follow the OpenA2A spec-family ladder `MAJOR.MINOR.PATCH-{draft|rcN|final}`;
the ATX **credential wire format** version (`atcVersion` `1.0` / `1.1`) is a separate
identifier registered in `core.md` §14.

## [Unreleased]

### Added

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
- `scripts/test_schema.py`: takes the §1.1 example credential, changes one member per case, and
  asserts that `schemas/atx-credential-v1.1.schema.json` accepts the result when `core.md` allows
  it and rejects it when `core.md` forbids it. The cases cover the taskScope and capability
  grammars, the keys and values of `capabilityJustification`, an absent, null or empty
  `declaredPurpose`, and the canonical empties of §1.3a.2 rules 1 and 2. It needs python3 and the
  `jsonschema` package, as `scripts/validate_examples.py` does, and is not yet run by CI.

### Changed

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
- `scalability.md` and `sovereign-federation.md` describe only credential members and mechanisms
  that the schema and `core.md` define. `scalability.md` §9.1 said the build plugin mints ATX
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
- core.md §2 item 5 previously promised signed CRL endpoints, delta CRLs and a push
  notification format; it now states what ATP-SPEC v1.0.0-rc1 §8.1 actually defines — the
  since-timestamp revocation response, its schema and the client refresh cadence — with the
  §8.1 revocation response body left unsigned in ATP 1.0 and a signed revocation list named
  as ATP 1.1 work.

### Added

- `schemas/atx-credential-v1.1.schema.json`: machine-readable JSON Schema
  (draft 2020-12) for the ATX credential wire form, derived from §1.1/§1.3a/§1.5
  with the atx-conformance fixtures as ground truth. All 15 fixtures validate as
  intended (14 shape-valid; `malformed-schema` fails on exactly the `atcVersion`
  registry enum).
- `scripts/validate_examples.py` + `schemas/examples-map.json` + CI workflow:
  every schema is metaschema-checked and the §1.1 example is validated against
  the schema on every push and PR.

### Changed

- `core.md` §1.1: the credential illustration is now wire-shape-accurate and
  schema-valid — field name `atcVersion` (previously shown under the `atxVersion`
  alias), bare-hex `contentHash`, provenance-URI `buildAttestation`,
  `scanSummary` with `highFindings` and the wire spellings `cryptoServe` /
  `no-weak-crypto`, `trustScore` on the wire's 0-100 scale, full-DID `keyId`
  values, and the issuance envelope fields `id` / `revoked` / `createdAt`.
- `core.md` §2 and §14: the `did:opena2a` type-prefix set now matches the
  did-method registry — `registry` added; `a2a_agent` documented as a deprecated
  legacy alias of `agent`, not a registered type.

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
