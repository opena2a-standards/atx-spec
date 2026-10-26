> **OpenA2A specs** · [did:opena2a](https://github.com/opena2a-standards/did-method-opena2a) · [AIP](https://github.com/opena2a-standards/agent-identity-protocol) · **ATX** · [ATP](https://github.com/opena2a-standards/agent-trust-protocol) · [AAP](https://github.com/opena2a-standards/agent-authorization-protocol) · [OpenA2A AIM (Agent Identity Management)](https://github.com/opena2a-org/agent-identity-management) · [all specs ↗](https://specs.opena2a.org)

# atx-spec

Architecture specifications for the **Agent Trust eXtension (ATX)** credential format and the **Agent Trust Protocol (ATP)** that issues, verifies, and revokes it.

## Start here

Read [`core.md`](core.md#13-local-verification-algorithm) first: section 1.3 is the algorithm every verifier runs, and section 1.1 the credential it checks.

To check a verifier against the pinned fixtures, run the reference verifier shown under the [first use case](#a-strangers-agent-calls-you-and-you-cannot-phone-home-on-every-request).

## What it does

### A stranger's agent calls you and you cannot phone home on every request

ATX is a signed, self-contained credential that carries the agent's identity, scan results, capabilities and behavioral profile.

A verifier checks the signature, the expiry and a locally cached revocation list, in under 5 ms on a warm cache, and never queries the issuing node during verification.

What you can do today: run the reference verifier against the pinned fixtures from a clean clone.

```sh
git clone https://github.com/opena2a-standards/atx-conformance
cd atx-conformance/verifiers/go
go run . ../../fixtures
# summary: 36 pass, 0 fail (36 fixtures)
```

Where it stops today: an ATX is a bearer artifact.

Presenting it proves what was attested about the agent build, not that the presenter is that agent, so a deployment pairs ATX presentation with proof of the presenter's identity, as [AAP broker profile §6.8](https://github.com/opena2a-standards/agent-authorization-protocol/blob/main/AAP-BROKER-PROFILE.md#68-presentation-binding) defines it: over a network, a proof-of-possession channel such as the AIP challenge; on a local socket, the OS peer credentials of the presenting process.

### The agent you approved last week is not the one acting now

An ATX lives for 7 days.

Renewal runs the build plugin and the scan again, so a fresh credential describes the current build, and an agent that must be stopped sooner is placed on a revocation list that verifiers check on every verification.

Where it stops today: a verifier whose cached revocation list is more than five minutes old refreshes it in the background and still allows the current request on the stale list.

### An auditor asks what each agent was allowed to attempt, and what scanned it

ATX 1.1 signs capabilities, the scan summary and the declared purpose inside the credential's canonical bytes, so a field changed after signing fails verification instead of passing unnoticed.

Where it stops today: capabilities in an ATX describe what the build is attested to be able to do.

They are not permission. Whether an agent may touch a given resource is a broker policy decision under AAP.

## Documentation

| Doc | Scope |
|---|---|
| [`core.md`](core.md) | ATX schema and lifecycle, ATP protocol surface (5 planes), local-verify algorithm, federation, transparency log, product integration map |
| [`scalability.md`](scalability.md) | Scaling properties: revocation propagation, CRL caching, transparency log scaling and monitor cost (the monitor verification cycle is [`core.md`](core.md) §6.4) |
| [`sovereign-federation.md`](sovereign-federation.md) | Multi-authority cosigning, sovereign-node operation, cross-org trust |
| [`docs/status.md`](docs/status.md) | Document version, the normative wire format, which OpenA2A service issues ATX and which verifies it, the ATP and AIP specifications |
| [`docs/use-cases.md`](docs/use-cases.md) | Each use case in full, with what you can do today and where it stops |
| [`docs/conformance.md`](docs/conformance.md) | Byte-stable fixtures and SDK-independent reference verifiers at [atx-conformance](https://github.com/opena2a-standards/atx-conformance), what they cover, the credential JSON Schema; conformance targets in [`core.md`](core.md) §12 |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Early and authored in the open: co-authors, an independent second implementation and cryptographic review are wanted before an external standards body |

To report a second-party implementation of ATX issuance or verification, open an issue on this repository.

## License

Apache 2.0. See [LICENSE](LICENSE).
