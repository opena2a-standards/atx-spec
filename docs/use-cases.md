# Use cases: reference detail

Text moved out of the [README](../README.md), kept here in full: the summary that opened it, the detail its use cases link to, and the use cases themselves.

## What ATX is

ATX is a signed, self-contained credential carried by every AI agent. It is analogous to a TLS certificate but contains agent identity, scan results, capabilities, and behavioral profile. Local verification under 5ms. Ed25519 + ML-DSA-65 hybrid signatures mandatory at v1.

## The agent you approved last week is not the one acting now

Where it stops today: a verifier whose cached revocation list is more than five minutes old refreshes it in the background and still allows the current request on the stale list. The `fixtures/revoked.json` credential also carries `revoked: true`, a field outside the signed bytes, so a verifier that never reads the revocation list still rejects it; `fixtures/revoked-crl-only.json` carries `revoked: false` with its agent on the verifier's list, so that verifier wrongly accepts it. No fixture exercises the five-minute bound or a request served on a stale list.

## Use cases

The README keeps a shorter form of each under What it does, and the reference verifier's commands under the first.

### A stranger's agent calls you and you cannot phone home on every request

A partner's agent calls your service. You want to know who issued its credential, what it was attested to do and whether it is still trusted, and you want that on every request, which rules out calling a central server each time: that is slow, and the server becomes the one thing whose outage takes you down.

ATX is a signed, self-contained credential that carries the agent's identity, scan results, capabilities and behavioral profile. A verifier checks the signature, the expiry and a locally cached revocation list, in under 5 ms on a warm cache, and never queries the issuing node during verification.

What you can do today: run the reference verifier against the pinned fixtures from a clean clone, with the commands under the [first use case in the README](../README.md#a-strangers-agent-calls-you-and-you-cannot-phone-home-on-every-request).

Or try to forge a signed object in your browser at [specs.opena2a.org/lab/forge](https://specs.opena2a.org/lab/forge): the lab signs a simplified object, not an ATX credential, so its verdicts are not conformance results.

Where it stops today: an ATX is a bearer artifact. Presenting it proves what was attested about the agent build, not that the presenter is that agent, so a deployment pairs ATX presentation with a proof-of-possession channel such as the AIP challenge.

### The agent you approved last week is not the one acting now

An agent passed review once and kept its credential for a year. A new build shipped, or an instruction hidden in a page changed how it behaves, and nothing re-checked it. The people relying on the review are trusting a result that no longer describes the agent.

An ATX lives for 7 days. Renewal runs the build plugin and the scan again, so a fresh credential describes the current build, and an agent that must be stopped sooner is placed on a revocation list that verifiers check on every verification.

What you can do today: the `fixtures/expired.json` and `fixtures/revoked.json` cases in the conformance suite are rejections a conforming verifier must reproduce, and the forge lab lets you advance the clock past the expiry of a simplified object it signs, which is not an ATX credential.

Where it stops today: a verifier whose cached revocation list is more than five minutes old refreshes it in the background and still allows the current request on the stale list. No fixture exercises the five-minute bound or a request served on a stale list. The two revoked fixtures are compared in [the section above](#the-agent-you-approved-last-week-is-not-the-one-acting-now).

### An auditor asks what each agent was allowed to attempt, and what scanned it

Your inventory of agents is a spreadsheet. The auditor asks for proof that the capabilities and scan results in it were not edited after the incident.

ATX 1.1 signs capabilities, the scan summary and the declared purpose inside the credential's canonical bytes, so a field changed after signing fails verification instead of passing unnoticed.

What you can do today: `fixtures/v1_1-tampered-capabilities.json`, whose capabilities were escalated to `system:exec` after signing, rejects with `SIGNATURE_INVALID` in both reference verifiers.

Where it stops today: capabilities in an ATX describe what the build is attested to be able to do. They are not permission. Whether an agent may touch a given resource is a broker policy decision under AAP.

Why you can check this yourself: [`core.md`](../core.md) is the specification and [`schemas/atx-credential-v1.1.schema.json`](../schemas/atx-credential-v1.1.schema.json) the machine-readable wire shape; [atx-conformance](https://github.com/opena2a-standards/atx-conformance) ships byte-pinned fixtures, Go and Python verifiers that each check both signature suites, and the `jcs-vectors/` canonical-bytes gate; OpenA2A AIM (Agent Identity Management) at [opena2a-org/agent-identity-management](https://github.com/opena2a-org/agent-identity-management) verifies ATX, and the OpenA2A Registry at `api.oa2a.org` issues it.
