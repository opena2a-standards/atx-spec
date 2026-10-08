> **OpenA2A specs** · [did:opena2a](https://github.com/opena2a-standards/did-method-opena2a) · [AIP](https://github.com/opena2a-standards/agent-identity-protocol) · **ATX** · [ATP](https://github.com/opena2a-standards/agent-trust-protocol) · [AAP](https://github.com/opena2a-standards/agent-authorization-protocol) · [OpenA2A AIM (Agent Identity Management)](https://github.com/opena2a-org/agent-identity-management) · [all specs ↗](https://specs.opena2a.org)

# atx-spec

Architecture specifications for the **Agent Trust eXtension (ATX)** credential format and the **Agent Trust Protocol (ATP)** that issues, verifies, and revokes it.

ATX is a signed, self-contained credential carried by every AI agent. It is analogous to a TLS certificate but contains agent identity, scan results, capabilities, and behavioral profile. Local verification under 5ms. Ed25519 + ML-DSA-65 hybrid signatures mandatory at v1.

## Use cases

### A stranger's agent calls you and you cannot phone home on every request

A partner's agent calls your service. You want to know who issued its credential, what it was attested to do and whether it is still trusted, and you want that on every request, which rules out calling a central server each time: that is slow, and the server becomes the one thing whose outage takes you down.

ATX is a signed, self-contained credential that carries the agent's identity, scan results, capabilities and behavioral profile. A verifier checks the signature, the expiry and a locally cached revocation list, in under 5 ms, and never queries the issuing node during verification.

What you can do today: run the reference verifier against the pinned fixtures from a clean clone.

```sh
git clone https://github.com/opena2a-standards/atx-conformance
cd atx-conformance/verifiers/go
go run . ../../fixtures
# summary: 23 pass, 0 fail (23 fixtures)
```

Or try to forge one in your browser at [specs.opena2a.org/lab/forge](https://specs.opena2a.org/lab/forge).

Where it stops today: an ATX is a bearer artifact. Presenting it proves what was attested about the agent build, not that the presenter is that agent, so a deployment pairs ATX presentation with a proof-of-possession channel such as the AIP challenge.

### The agent you approved last week is not the one acting now

An agent passed review once and kept its credential for a year. A new build shipped, or an instruction hidden in a page changed how it behaves, and nothing re-checked it. The people relying on the review are trusting a result that no longer describes the agent.

An ATX lives for 7 days. Renewal runs the build plugin and the scan again, so a fresh credential describes the current build, and an agent that must be stopped sooner is placed on a revocation list that verifiers check on every verification.

What you can do today: the `fixtures/expired.json` and `fixtures/revoked.json` cases in the conformance suite are rejections a conforming verifier must reproduce, and the forge lab lets you present a credential past its lifetime.

Where it stops today: a verifier whose cached revocation list is more than five minutes old refreshes it in the background and still allows the current request on the stale list.

### An auditor asks what each agent was allowed to attempt, and what scanned it

Your inventory of agents is a spreadsheet. The auditor asks for proof that the capabilities and scan results in it were not edited after the incident.

ATX 1.1 signs capabilities, the scan summary and the declared purpose inside the credential's canonical bytes, so a field changed after signing fails verification instead of passing unnoticed.

What you can do today: `fixtures/v1_1-tampered-capabilities.json`, whose capabilities were escalated to `system:exec` after signing, rejects with `SIGNATURE_INVALID` in both reference verifiers.

Where it stops today: capabilities in an ATX describe what the build is attested to be able to do. They are not permission. Whether an agent may touch a given resource is a broker policy decision under AAP.

Why you can check this yourself: [`core.md`](core.md) is the specification and [`schemas/atx-credential-v1.1.schema.json`](schemas/atx-credential-v1.1.schema.json) the machine-readable wire shape; [atx-conformance](https://github.com/opena2a-standards/atx-conformance) ships 23 byte-pinned fixtures, Go and Python verifiers that each check both signature suites, and the `jcs-vectors/` canonical-bytes gate; the [forge lab](https://specs.opena2a.org/lab/forge) runs the same checks in a browser; OpenA2A AIM (Agent Identity Management) at [opena2a-org/agent-identity-management](https://github.com/opena2a-org/agent-identity-management) verifies ATX, and the OpenA2A Registry at `api.oa2a.org` issues it.

## Contributing

This specification is early and authored in the open. We are looking for co-authors, an independent second implementation, and cryptographic review before it goes to an external standards body. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Documents

| Doc | Scope |
|---|---|
| [`core.md`](core.md) | ATX schema and lifecycle, ATP protocol surface (5 planes), local-verify algorithm, federation, transparency log, product integration map |
| [`scalability.md`](scalability.md) | Scaling properties: revocation propagation, CRL caching, transparency log monitor protocol |
| [`sovereign-federation.md`](sovereign-federation.md) | Multi-authority cosigning, sovereign-node operation, cross-org trust |

## Status

Architecture specifications, document version 1.1.0-final (July 2026; first published May 2026). The normative credential wire format is **ATX 1.1** (JCS canonical signing form, [`core.md`](core.md) §1.3a.2) — this is what production issuance emits; ATX 1.0 is frozen legacy with a documented transition rule (§1.3a.5). OpenA2A's issuing node is the OpenA2A Registry service. OpenA2A AIM (Agent Identity Management), at [`opena2a-org/agent-identity-management`](https://github.com/opena2a-org/agent-identity-management), verifies ATX and does not issue it. AIM requests ATX from the Registry for the agents registered with it. Changes are tracked in [`CHANGELOG.md`](CHANGELOG.md).

ATX/ATP/AIP cross-reference: see [`opena2a-org/agent-trust-protocol`](https://github.com/opena2a-org/agent-trust-protocol) for the ATP wire protocol spec and [`opena2a-org/agent-identity-protocol`](https://github.com/opena2a-org/agent-identity-protocol) for the AIP identity spec.

## Conformance

Byte-stable conformance fixtures and SDK-independent reference verifiers for ATX v1.0 and v1.1 live at [`opena2a-standards/atx-conformance`](https://github.com/opena2a-standards/atx-conformance). The suite ships 23 fixtures — the v1.0 set (baseline valid, hybrid Ed25519 plus ML-DSA-65, threshold 2-of-3 cosignature, revoked, expired, wrong-issuer, cross-issuer-key, tampered-signature, malformed-schema) plus the `v1_1-*` family (JCS-form baselines, signed-field integrity via tampered `capabilities`, issuer binding, an untrusted chain authority that contributes no eligible key even when named in the signed `issuerChain`, `declaredPurpose` carried under the signature, the §1.3a.2 rule-5 degenerate inputs — whitespace-empty object accepted as absent, injected array/string values rejected — and strict credential parse: duplicate object members rejected at any depth per RFC 8259 §4, and case-variant members that a last-wins JSON decoder would collapse rejected as `PARSE_ERROR`, and a hybrid credential whose ML-DSA-65 signature is forged while its Ed25519 signature stays intact, which every declared signature having to verify rejects, and a credential omitting the optional `transparencyLogIndex`, which a verifier that still requires the field wrongly rejects) — each pinned by SHA-256 in `MANIFEST.sha256`, plus two reference verifiers that each verify both declared signature suites: Go (via Cloudflare CIRCL) and Python (via `dilithium-py`, FIPS 204). Both verifiers report 23 of 23 PASS against the shipped fixture set, and the suite's `jcs-vectors/` gate pins the cross-language `JCS(TBS)` byte agreement that [`core.md`](core.md) §1.3a.3 makes mandatory. Conformance targets (credential, issuer, verifier) are defined in [`core.md`](core.md) §12. The credential wire shape is additionally published as a machine-readable JSON Schema at [`schemas/atx-credential-v1.1.schema.json`](schemas/atx-credential-v1.1.schema.json), CI-validated against the §1.1 example here and against the fixture set in the conformance suite.

To report a second-party implementation of ATX issuance or verification, open an issue on this repository.

## License

Apache 2.0. See [LICENSE](LICENSE).
