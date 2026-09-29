# Changelog

All notable changes to the ATX architecture specifications are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Document
versions follow the OpenA2A spec-family ladder `MAJOR.MINOR.PATCH-{draft|rcN|final}`;
the ATX **credential wire format** version (`atcVersion` `1.0` / `1.1`) is a separate
identifier registered in `core.md` §14.

## [Unreleased]

### Added

- `errata/`: published ATX text is now corrected through numbered errata rather
  than silent edits. An erratum is one file, `errata/ATX-E-NNNN.md`, whose
  frontmatter carries `id`, `status`, `class`, `affectsDocument`, `affectsWire`,
  `sections`, `oldText`, `newText`, `fixtures`, `filed` and `accepted` — the
  published text and its replacement verbatim, so a reader can apply the
  correction without judgement. Acceptance of an erratum is a document PATCH on
  the version ladder. `errata/README.md` is generated from those files by
  `scripts/gen_errata_index.py` and `core.md`'s header names it and the highest
  incorporated erratum. No erratum has been filed yet; this is the mechanism.
- `scripts/check_errata.py` + `scripts/test_errata.sh`, wired into
  `.github/workflows/conformance-counts.yml` after the count check and against
  the same atx-conformance checkout: an erratum whose class is not `editorial`
  cannot be accepted while it names no conformance fixture, or names one the
  suite does not contain — the corrected behaviour has to be observable, not
  just written down. The guard also fails an accepted erratum missing from this
  changelog, a stale index, a frontmatter key that is not in the contract, a
  duplicate or misnamed id, and a `security` erratum still `proposed` under a
  header that already claims it as incorporated. Per Binding Decision 10 it
  additionally fails any implementation name or implementation status appearing
  under `errata/`: the public text says what the specification requires, and the
  conformance suite reports who passes.

### Changed

- The name OpenA2A AIM (Agent Identity Management) is written in full where `README.md`,
  `CONTRIBUTING.md`, `core.md` and `sovereign-federation.md` first use it in running text. `core.md`
  gains an informative paragraph at the end of "Conventions and terminology" that says what AIM is
  and that the document calls it AIM. No normative text changes.
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
