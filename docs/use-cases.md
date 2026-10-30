# Use cases: reference detail

Text moved out of the [README](../README.md), kept here in full: the summary that opened it, the detail its use cases link to, and the use cases themselves. The page also names who reads the specification and where each reader's question is answered, and adds two use cases, for the security leader and for the identity architect.

## What ATX is

ATX is a signed, self-contained credential carried by every AI agent. It is analogous to a TLS certificate but contains agent identity, scan results, capabilities, and behavioral profile. Local verification under 5ms. Ed25519 + ML-DSA-65 hybrid signatures mandatory at v1.

## Who reads this

Each row names a reader, the question that brings them here and the text that answers it. A `core.md:N` reference is the line in `core.md` at the commit that added this table; the section link stays stable when lines move.

| Reader | The question they bring | Where it is answered |
|---|---|---|
| Security leader or CISO | What risk does ATX reduce, what do I require of a vendor, and what evidence do I get? | [A vendor's agent arrives with a credential its own authority signed](#a-vendors-agent-arrives-with-a-credential-its-own-authority-signed); the conformance targets of [§12](../core.md#12-conformance) (`core.md:960`); the security considerations of [§13](../core.md#13-security-considerations) (`core.md:979`) |
| IAM professional or identity architect | Where does ATX sit beside the certificates, tokens and DIDs I already run, and what does it not replace? | [Your identity team asks where ATX sits beside what it runs](#your-identity-team-asks-where-atx-sits-beside-what-it-runs); [§1.4](../core.md#14-atx-versus-tls-certificate) (`core.md:533`); [§10](../core.md#10-what-atx-is-not) (`core.md:932`); issuer key resolution, [§1.3 step 3](../core.md#13-local-verification-algorithm) (`core.md:139`) |
| Platform or security engineer | How do I run a verifier on the request path, and what does a failure look like? | [A stranger's agent calls you](#a-strangers-agent-calls-you-and-you-cannot-phone-home-on-every-request); [The agent you approved last week](#the-agent-you-approved-last-week-is-not-the-one-acting-now-1); the eight steps of [§1.3](../core.md#13-local-verification-algorithm) (`core.md:132`); revocation staleness in [§13](../core.md#13-security-considerations) (`core.md:993`); transparency-log monitors, [§6.4](../core.md#64-monitors) (`core.md:866`) |
| Agent developer or implementer | What do I implement first, and how do I show it works? | [§1.3](../core.md#13-local-verification-algorithm), then the canonical signing form of [§1.3a.2](../core.md#13a2-jcs-form-atcversion--11) (`core.md:186`); the Verifier target and the Coverage paragraph of [§12](../core.md#12-conformance) (`core.md:969`, `core.md:975`); the reference verifier command under the [first use case in the README](../README.md#a-strangers-agent-calls-you-and-you-cannot-phone-home-on-every-request) |
| GRC, audit or compliance reader | Which controls does it support, and what does an auditor read? | [An auditor asks what each agent was allowed to attempt](#an-auditor-asks-what-each-agent-was-allowed-to-attempt-and-what-scanned-it); Threat Matrix technique IDs in `scanSummary.techniques` (`core.md:119`) and in the titles of the five [§13](../core.md#13-security-considerations) paragraphs that cite a technique by ID (`core.md:983` to `core.md:991`); the OASB level member `scanSummary.oasbLevel` of the [v1.1 credential schema](../schemas/atx-credential-v1.1.schema.json) (line 120); the transparency log of [§6](../core.md#6-transparency-log) (`core.md:820`) |
| Standards reviewer (IETF or AIW participant) | What problem does this solve, how does it relate to existing work, and how mature is the text? | [§0](../core.md#0-the-reframe) (`core.md:24`); the comparison with a TLS certificate in [§1.4](../core.md#14-atx-versus-tls-certificate) (`core.md:533`); the registries of [§14](../core.md#14-registry-considerations) (`core.md:1003`); document version and status in [`docs/status.md`](status.md); the review and second implementation wanted, [`CONTRIBUTING.md`](../CONTRIBUTING.md) |

### The readers

- **Security leader or CISO**
  - Who: accountable for the organization's security risk, and for which agents and vendors may act on its systems.
  - Why they open it: a vendor or an internal team says its agents are verified, and the word needs a meaning that can be written into a requirement.
  - What they decide: which issuers to trust, which conformance targets to require, and which decisions may rest on a credential's trust level.
  - How they verify: the reference verifier's verdicts on the pinned fixtures, and the self-attestation [§12](../core.md#12-conformance) requires for the requirements no fixture covers.
- **IAM professional or identity architect**
  - Who: runs the identity systems the organization already has, such as OAuth 2.0 and OpenID Connect, X.509 certificates, workload identity such as SPIFFE, DIDs and privileged access management.
  - Why they open it: a proposal to add ATX for agents reaches the identity team, which must say what it overlaps with.
  - What they decide: where the credential is presented and verified, which system supplies the agent's identity, and how presentation is bound to the presenter.
  - How they verify: [§1.4](../core.md#14-atx-versus-tls-certificate), [§10](../core.md#10-what-atx-is-not) and the Stolen credentials paragraph of [§13](../core.md#13-security-considerations), and the key-eligibility fixture shown below.
- **Platform or security engineer**
  - Who: deploys, operates and monitors the components that check agents at runtime, and is paged when they fail.
  - Why they open it: they will run the verifier on the request path and need its failure behavior before they deploy it.
  - What they decide: cache lifetimes within the bounds the specification sets, what to log for each rejection reason, and whether to watch the transparency log.
  - How they verify: the reference verifier against the pinned fixtures, then their own verifier against the same fixtures.
- **Agent developer or implementer**
  - Who: writes the issuer, the verifier or the agent that presents the credential.
  - Why they open it: they have to produce or check credentials that other implementations accept.
  - What they decide: which conformance target to claim (credential, issuer or verifier) and the order to build it in.
  - How they verify: the fixtures of [atx-conformance](https://github.com/opena2a-standards/atx-conformance) through their implementation, compared with the pinned verdicts, and its `jcs-vectors/` canonical-bytes gate.
- **GRC, audit or compliance reader**
  - Who: maps controls to evidence and reads the records an auditor asks for.
  - Why they open it: an auditor asks what each agent was attested to do, what scanned it and when its trust changed.
  - What they decide: which records count as evidence, and which control each record supports.
  - How they verify: a credential whose fields were changed after signing fails verification, as the tampered-capabilities fixture shows, and the issuance and revocation entries in the issuer's transparency log where the issuer exposes it for reading.
- **Standards reviewer (IETF or AIW participant)**
  - Who: a participant in an IETF or AIW discussion who judges whether a problem needs new work.
  - Why they open it: to see what problem ATX addresses, how it relates to certificates and Certificate Transparency, and how mature the text is.
  - What they decide: whether to review, co-author or implement it, and what to ask the editors to change.
  - How they verify: the conformance suite, the status line at the top of `core.md`, and whether an independent second implementation exists, which [`CONTRIBUTING.md`](../CONTRIBUTING.md) asks for.

## The agent you approved last week is not the one acting now

Where it stops today: a verifier whose cached revocation list is more than five minutes old refreshes it in the background and still allows the current request on the stale list. The `fixtures/revoked.json` credential also carries `revoked: true`, a field outside the signed bytes, so a verifier that rejects on that field and never reads the revocation list still rejects it; `fixtures/revoked-crl-only.json` carries `revoked: false` with its agent on the verifier's list, so that verifier wrongly accepts it. No fixture exercises the five-minute bound or a request served on a stale list.

## Use cases

The README keeps a shorter form of the first three under What it does, and the reference verifier's commands under the first. The last two answer the security leader and the identity architect of the reader table above.

### A stranger's agent calls you and you cannot phone home on every request

A partner's agent calls your service. You want to know who issued its credential, what it was attested to do and whether it is still trusted, and you want that on every request, which rules out calling a central server each time: that is slow, and the server becomes the one thing whose outage takes you down.

ATX is a signed, self-contained credential that carries the agent's identity, scan results, capabilities and behavioral profile. A verifier checks the signature, the expiry and a locally cached revocation list, in under 5 ms on a warm cache, and never queries the issuing node during verification.

What you can do today: run the reference verifier against the pinned fixtures from a clean clone, with the commands under the [first use case in the README](../README.md#a-strangers-agent-calls-you-and-you-cannot-phone-home-on-every-request).

Or try to forge a signed object in your browser at [specs.opena2a.org/lab/forge](https://specs.opena2a.org/lab/forge): the lab signs a simplified object, not an ATX credential, so its verdicts are not conformance results.

Where it stops today: an ATX is a bearer artifact. Presenting it proves what was attested about the agent build, not that the presenter is that agent, so a deployment pairs ATX presentation with proof of the presenter's identity, as [AAP broker profile §6.8](https://github.com/opena2a-standards/agent-authorization-protocol/blob/main/AAP-BROKER-PROFILE.md#68-presentation-binding) defines it: over a network, a proof-of-possession channel such as the AIP challenge; on a local socket, the OS peer credentials of the presenting process.

Who acts: the platform or security engineer who runs the verifier in front of a service.

Spec text: the local verification algorithm of [§1.3](../core.md#13-local-verification-algorithm) (`core.md:132`); the Verifier target of [§12](../core.md#12-conformance) (`core.md:969`), under which a conforming verifier MUST NOT add a network dependency on the issuing node to the acceptance path; and the Stolen credentials replay paragraph of [§13](../core.md#13-security-considerations) (`core.md:985`), under which a deployment where impersonation matters MUST pair presentation with proof of the presenter's identity.

### The agent you approved last week is not the one acting now

An agent passed review once and kept its credential for a year. A new build shipped, or an instruction hidden in a page changed how it behaves, and nothing re-checked it. The people relying on the review are trusting a result that no longer describes the agent.

An ATX lives for 7 days. Renewal runs the build plugin and the scan again, so a fresh credential describes the current build, and an agent that must be stopped sooner is placed on a revocation list that verifiers check on every verification.

What you can do today: the `fixtures/expired.json` and `fixtures/revoked.json` cases in the conformance suite are rejections a conforming verifier must reproduce, and the forge lab lets you advance the clock past the expiry of a simplified object it signs, which is not an ATX credential.

Where it stops today: a verifier whose cached revocation list is more than five minutes old refreshes it in the background and still allows the current request on the stale list. No fixture exercises the five-minute bound or a request served on a stale list. The two revoked fixtures are compared in [the section above](#the-agent-you-approved-last-week-is-not-the-one-acting-now).

Who acts: the security leader who approved the agent, and the engineer whose verifier must stop accepting it.

Spec text: the seven-day lifetime and renewal of [§1.2](../core.md#12-atx-lifecycle) (`core.md:129`); the validity window of [§1.3](../core.md#13-local-verification-algorithm) step 2 (`core.md:138`) and its revocation check, step 6 (`core.md:145`); and the Revocation staleness paragraph of [§13](../core.md#13-security-considerations) (`core.md:993`), under which the five-minute staleness bound MUST be documented to relying parties.

### An auditor asks what each agent was allowed to attempt, and what scanned it

Your inventory of agents is a spreadsheet. The auditor asks for proof that the capabilities and scan results in it were not edited after the incident.

ATX 1.1 signs capabilities, the scan summary and the declared purpose inside the credential's canonical bytes, so a field changed after signing fails verification instead of passing unnoticed.

What you can do today: `fixtures/v1_1-tampered-capabilities.json`, whose capabilities were escalated to `system:exec` after signing, rejects with `SIGNATURE_INVALID` in both reference verifiers.

Where it stops today: capabilities in an ATX describe what the build is attested to be able to do. They are not permission. Whether an agent may touch a given resource is a broker policy decision under AAP.

Who acts: the auditor or GRC reader, and the issuer whose credentials they read.

Spec text: the JCS signing form of [§1.3a.2](../core.md#13a2-jcs-form-atcversion--11) (`core.md:186`), which brings `capabilities` and `scanSummary` inside the signed bytes; the Unsigned v1.0 fields paragraph of [§13](../core.md#13-security-considerations) (`core.md:983`), under which a consumer making decisions on those fields MUST require v1.1; and the Issuer target of [§12](../core.md#12-conformance) (`core.md:967`), under which every issuance and revocation is logged to the transparency log before it takes effect.

### A vendor's agent arrives with a credential its own authority signed

A vendor offers an agent that will act on your systems and says it is verified. The credential it carries was signed by the vendor's own authority, so unless something independent stands behind it, the statement is the vendor vouching for itself. You need a requirement you can write into the contract and check on every request.

Who acts: the security leader who sets the requirement, and the verifier at the edge of the organization that applies it.

Without the specification: "verified" is a word in a sales document. Nothing ties it to a key your organization chose to trust, and nothing tells a reviewer which independent parties stood behind it.

What the specification does: a verifier accepts a signature only under a key resolved for an authority it trusts for that credential ([§1.3](../core.md#13-local-verification-algorithm) step 4, `core.md:140`), and it rejects an issuer outside its federation trust list even when the signature itself is valid (the Key substitution at resolution paragraph of [§13](../core.md#13-security-considerations), `core.md:989`). When trust level 3 or higher is required, the verifier MUST reject the credential unless at least two distinct authorities each produced a signature it verified itself (step 7, `core.md:146`), and a conforming issuer MUST NOT assert that level without them (the Issuer target of [§12](../core.md#12-conformance), `core.md:967`). For the requirements no fixture exercises yet, an implementation MUST self-attest against the sections the Coverage paragraph of §12 names (`core.md:975`).

What to ask a vendor for, in the specification's terms: credentials that a verifier conforming to the Verifier target of §12 accepts; an issuing authority on your own trust list; signatures from two distinct authorities for any decision that requires trust level 3 or higher; issuance and revocation entries in the issuer's transparency log; and the §12 self-attestation for the requirements the suite does not cover.

How to see it work: the `wrong-issuer` fixture carries a valid signature from an authority the verifier does not trust, and the reference verifier rejects it.

```sh
git clone https://github.com/opena2a-standards/atx-conformance
cd atx-conformance/verifiers/go
go run . ../../fixtures/wrong-issuer.json
```

Output at atx-conformance commit `2328506`, run on 2026-10-30:

```
PASS  ../../fixtures/wrong-issuer.json
       expected: REJECT [UNTRUSTED_ISSUER]
       observed: REJECT[UNTRUSTED_ISSUER: issuer DID did:opena2a:authority:attacker.example is not in the verifier's trusted set (untrusted issuer)]

summary: 1 pass, 0 fail (1 fixture)
```

Out of scope: the suite cannot show the two-authority count. No fixture carries signatures from more than one distinct authority, so a verifier that omits step 7 entirely passes it, and that requirement is self-attested (Coverage, `core.md:975`). Which authorities belong on your trust list is your decision; the specification says how the list is applied, not who is on it. A trusted credential says what was attested about the build. It is not permission, which is the AAP broker's decision ([§10](../core.md#10-what-atx-is-not), `core.md:937`).

### Your identity team asks where ATX sits beside what it runs

Your organization already issues certificates to its services and tokens to its applications, and some teams publish DIDs. Someone proposes ATX for agents. Before agreeing, the identity team needs to know what ATX replaces, what it adds and where it plugs in.

Who acts: the IAM professional or identity architect.

Without the specification: an agent borrows a credential made for something else, such as a service's TLS certificate, which identifies a domain or a server and carries no scan results or behavioral profile ([§1.4](../core.md#14-atx-versus-tls-certificate), `core.md:533`), or it carries nothing and the receiving side guesses.

What the specification does: ATX replaces neither the identity system nor the authorization system. [§10](../core.md#10-what-atx-is-not) (`core.md:936`, architectural text) leaves the agent's identity to an AIP identity provider such as OpenA2A AIM (Agent Identity Management) and access decisions to the AAP broker; ATX binds that identity to a build and a behavioral profile, lives seven days and is checked locally. It plugs in at three points:

- Presentation: the `Agent-Trust-Credential` HTTP header, an A2A agent card or an MCP server manifest ([§1.2](../core.md#12-atx-lifecycle), `core.md:127`).
- Issuer keys: the verifier resolves `issuerDid` through a cached DID document ([§1.3](../core.md#13-local-verification-algorithm) step 3, `core.md:139`); resolvers MUST fetch DID documents over authenticated channels, and a key counts only for an authority the verifier trusts for the credential (step 4, `core.md:140`; Key substitution at resolution, `core.md:989`).
- The presenter: an ATX is a bearer artifact, so a deployment where impersonation matters MUST pair its presentation with proof of the presenter's identity, in the form AAP broker profile §6.8 defines (Stolen credentials replay, `core.md:985`).

How to see it work: the `cross-issuer-key` fixture names one authority as its issuer and is signed with a key of a different trusted authority. The signature is valid over the canonical bytes, and the reference verifier still rejects it, because the key does not belong to the issuer.

```sh
cd atx-conformance/verifiers/go
go run . ../../fixtures/cross-issuer-key.json
```

Output at atx-conformance commit `2328506`, run on 2026-10-30:

```
PASS  ../../fixtures/cross-issuer-key.json
       expected: REJECT [SIGNATURE_INVALID]
       observed: REJECT[SIGNATURE_INVALID: Ed25519 signature did:opena2a:authority:partner.example#key-1 did not verify against any configured public key]

summary: 1 pass, 0 fail (1 fixture)
```

Out of scope: `core.md` defines no mapping onto OAuth 2.0, OpenID Connect, SPIFFE or an X.509 certificate profile, and does not say how an ATX travels beside an access token. An ATX does not authenticate its presenter (the binding above does), does not issue the agent's identity and does not grant access.

## Why you can check this yourself

Why you can check this yourself: [`core.md`](../core.md) is the specification and [`schemas/atx-credential-v1.1.schema.json`](../schemas/atx-credential-v1.1.schema.json) the machine-readable wire shape; [atx-conformance](https://github.com/opena2a-standards/atx-conformance) ships byte-pinned fixtures, Go and Python verifiers that each check both signature suites, and the `jcs-vectors/` canonical-bytes gate; OpenA2A AIM (Agent Identity Management) at [opena2a-org/agent-identity-management](https://github.com/opena2a-org/agent-identity-management) verifies ATX, and the OpenA2A Registry at `api.oa2a.org` issues it.
