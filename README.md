> **OpenA2A specs** · [did:opena2a](https://github.com/opena2a-standards/did-method-opena2a) · [AIP](https://github.com/opena2a-standards/agent-identity-protocol) · **ATX** · [ATP](https://github.com/opena2a-standards/agent-trust-protocol) · [AAP](https://github.com/opena2a-standards/agent-authorization-protocol) · [AIM](https://github.com/opena2a-org/agent-identity-management) · [all specs ↗](https://specs.opena2a.org)

# atx-spec

Architecture specifications for the **Agent Trust eXtension (ATX)** credential format and the **Agent Trust Protocol (ATP)** that issues, verifies, and revokes it.

ATX is a signed, self-contained credential carried by every AI agent. It is analogous to a TLS certificate but contains agent identity, scan results, capabilities, and behavioral profile. Local verification under 5ms. Ed25519 + ML-DSA-65 hybrid signatures mandatory at v1.

## Contributing

This specification is early and authored in the open. We are looking for co-authors, an independent second implementation, and cryptographic review before it goes to an external standards body. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Documents

| Doc | Scope |
|---|---|
| [`core.md`](core.md) | ATX schema and lifecycle, ATP protocol surface (5 planes), local-verify algorithm, federation, transparency log, product integration map |
| [`scalability.md`](scalability.md) | Scaling properties: revocation propagation, CRL caching, transparency log monitor protocol |
| [`sovereign-federation.md`](sovereign-federation.md) | Multi-authority cosigning, sovereign-node operation, cross-org trust |

## Status

Architecture specifications, document version 1.1.0-final (July 2026; first published May 2026). The normative credential wire format is **ATX 1.1** (JCS canonical signing form, [`core.md`](core.md) §1.3a.2); ATX 1.0 is frozen legacy with a documented transition rule (§1.3a.5). Reference implementation: OpenA2A AIM (Agent Identity Management), tracked in [`opena2a-org/agent-identity-management`](https://github.com/opena2a-org/agent-identity-management). Changes are tracked in [`CHANGELOG.md`](CHANGELOG.md).

ATX/ATP/AIP cross-reference: see [`opena2a-org/agent-trust-protocol`](https://github.com/opena2a-org/agent-trust-protocol) for the ATP wire protocol spec and [`opena2a-org/agent-identity-protocol`](https://github.com/opena2a-org/agent-identity-protocol) for the AIP identity spec.

## Conformance

Byte-stable conformance fixtures and SDK-independent reference verifiers for ATX v1.0 and v1.1 live at [`opena2a-standards/atx-conformance`](https://github.com/opena2a-standards/atx-conformance). The suite ships 23 fixtures — the v1.0 set (baseline valid, hybrid Ed25519 plus ML-DSA-65, threshold 2-of-3 cosignature, revoked, expired, wrong-issuer, cross-issuer-key, tampered-signature, malformed-schema) plus the `v1_1-*` family (JCS-form baselines, signed-field integrity via tampered `capabilities`, issuer binding, an untrusted chain authority that contributes no eligible key even when named in the signed `issuerChain`, `declaredPurpose` carried under the signature, the §1.3a.2 rule-5 degenerate inputs — whitespace-empty object accepted as absent, injected array/string values rejected — and strict credential parse: duplicate object members rejected at any depth per RFC 8259 §4, and case-variant members that a last-wins JSON decoder would collapse rejected as `PARSE_ERROR`, and a hybrid credential whose ML-DSA-65 signature is forged while its Ed25519 signature stays intact, which every declared signature having to verify rejects, and a credential omitting the optional `transparencyLogIndex`, which a verifier that still requires the field wrongly rejects) — each pinned by SHA-256 in `MANIFEST.sha256`, plus two reference verifiers that each verify both declared signature suites: Go (via Cloudflare CIRCL) and Python (via `dilithium-py`, FIPS 204). Both verifiers report 23 of 23 PASS against the shipped fixture set, and the suite's `jcs-vectors/` gate pins the cross-language `JCS(TBS)` byte agreement that [`core.md`](core.md) §1.3a.3 makes mandatory. Conformance targets (credential, issuer, verifier) are defined in [`core.md`](core.md) §12. The credential wire shape is additionally published as a machine-readable JSON Schema at [`schemas/atx-credential-v1.1.schema.json`](schemas/atx-credential-v1.1.schema.json), CI-validated against the §1.1 example here and against the fixture set in the conformance suite.

Second-party implementations of ATX issuance or verification are tracked on [a2aproject/A2A#1876](https://github.com/a2aproject/A2A/issues/1876).

## License

Apache 2.0. See [LICENSE](LICENSE).
