# ATX sovereign federation architecture

**How governments and regulated industries stand up their own ATX platform**

Version 1.0. May 2026. This document is the sovereignty companion to the ATX core architecture. It defines how a government, a regulated industry, or any organization with jurisdictional or trust constraints stands up its own ATX issuing node, controls its own trust relationships, and federates selectively with the rest of the ecosystem.

The architectural goal: each sovereign decides who it trusts. No central authority can force a relationship. No foreign infrastructure can become the gatekeeper. The system survives any pattern of hostile relationships because federation is opt in at every edge.

This is what makes ATX deployable in environments that would never adopt a SaaS trust product. It is also what makes ATX a candidate to become the trust binding for sovereign AI infrastructure programs at the national level.

---

## 1. The sovereign requirement

Three structural realities drive the sovereign architecture.

**Jurisdictional control over agent identity.** When a government runs AI agents that handle citizen data, classified information, or critical infrastructure, those agents cannot be authenticated by a credential issued in another jurisdiction. The credential itself is regulatory evidence. The issuing authority must be subject to the jurisdiction's law.

**Data residency for credential metadata.** ATX credentials contain build attestations, scan results, behavioral profiles, and identity bindings. That data has residency requirements in many jurisdictions. GDPR, FedRAMP, the EU AI Act, NIS2, the UK GDPR, and emerging Chinese, Indian, and Korean AI laws all touch this data in different ways. A sovereign node keeps the data within the jurisdictional perimeter.

**Discretion over trust relationships.** A sovereign chooses who it trusts. It cannot be forced into a federation it does not want. It cannot be excluded from a federation it does want. The architecture must support trust lists that are entirely under sovereign control, including the case where two sovereigns refuse to recognize each other's credentials.

These three requirements are not deployment options. They are the constraints that make the architecture deployable to governments at all.

---

## 2. The sovereign node

A sovereign node is a full ATP authority that issues, revokes, and federates ATX credentials within and across the sovereign's jurisdiction. It is functionally identical to the root OpenA2A node, except for two things: it issues only for agents in its jurisdiction, and it cosigns only for relationships it chooses to recognize.

### 2.1 Deployment topology

A reference sovereign deployment includes:

* **Issuing CA service.** Receives build attestations, mints ATX, threshold signs with the sovereign's keys.
* **Transparency log.** Append only RFC 6962 Merkle tree, signed by sovereign keys, published locally.
* **CRL service.** Sovereign controlled revocation list, federated to other recognized nodes.
* **DID document service.** Publishes the sovereign's authority DID and key history.
* **Federation gateway.** Manages bilateral relationships, cosignature requests, trust list enforcement.
* **HSM cluster.** Hardware backed signing keys. The sovereign's private keys never leave the HSM.
* **Build attestation processor.** Validates submissions from sovereign approved CI environments.
* **Monitor.** Verifies the sovereign's own transparency log for self auditing.

The infrastructure can run on sovereign cloud, on dedicated data center hardware, or on classified networks with no internet connectivity at all. The architecture supports all three.

### 2.2 Minimum viable sovereign deployment

The smallest credible sovereign node is a single region deployment with high availability:

* 3 HSMs (2 of 3 threshold signing)
* 2 active issuing nodes (one primary, one standby, both can mint)
* 3 transparency log replicas
* 2 CRL distribution points
* 1 federation gateway (with hot standby)
* 1 monitor

This fits on roughly 20 cores of compute, 64 GB of memory, and a few TB of storage. It serves up to 100,000 agents at the capacity targets specified in the scalability doc. A nation state deployment scales up from here by adding regional replicas and additional HSMs.

### 2.3 Key custody

Sovereign signing keys must be controlled by the sovereign. Three patterns are valid:

| Pattern | Key custody | Use case |
|---|---|---|
| Fully sovereign HSM | All keys in sovereign owned HSM | Government, defense, intelligence |
| Sovereign cloud HSM | Keys in cloud HSM under sovereign cloud account | Regulated industry, allied nation |
| Shared custody | Threshold split between sovereign and external party | Bilateral consortium, regional bloc |

Threshold signing means that no single HSM holds the full signing capability. The sovereign defines the threshold (typically 2 of 3 or 3 of 5). Compromise of any single HSM does not compromise the sovereign's ability to sign.

### 2.4 Identity binding to the sovereign

Every ATX issued by a sovereign node carries an issuerDid that resolves to the sovereign's authority DID document. Example:

```
did:opena2a:authority:gov.uk
did:opena2a:authority:state.gov.us
did:opena2a:authority:digital.govt.nz
did:opena2a:authority:bsi.de
did:opena2a:authority:digital.go.jp
```

These DIDs are not under OpenA2A's control. Each sovereign publishes its own DID document at a sovereign controlled URL. The sovereign's keys, rotation policy, and revocation history are all sovereign published.

The result: a verifier looking at an ATX issued by gov.uk knows the credential was issued by UK government infrastructure, signed by UK government keys, governed by UK law.

---

## 3. Trust list management: who the sovereign trusts

The trust list is the heart of the sovereignty model. It is what makes "establish trust with who they want" architectural rather than aspirational.

### 3.1 Trust list semantics

A trust list is a sovereign maintained list of other authorities whose ATX credentials this sovereign will honor. Three states per authority:

| State | Behavior |
|---|---|
| Allowed | ATX issued by this authority is honored at the trust level the credential specifies. |
| Conditional | ATX is honored but trust level is capped at a sovereign defined ceiling (often level 2 or 3). |
| Denied | ATX issued by this authority is never honored. Verification fails regardless of credential validity. |

The trust list is not a global registry. Each sovereign maintains its own. Two sovereigns can have entirely different trust lists. A third sovereign can be on neither list.

### 3.2 Trust list operations

```
gov.uk trust list:
  did:opena2a:authority:opena2a.org        Allowed   (root, for community packages)
  did:opena2a:authority:gov.us             Allowed   (allied nation)
  did:opena2a:authority:europa.eu          Allowed   (regional bloc)
  did:opena2a:authority:digital.govt.nz    Allowed
  did:opena2a:authority:bsi.de             Allowed
  did:opena2a:authority:digital.go.jp      Allowed
  did:opena2a:authority:gc.ca              Allowed
  did:opena2a:authority:adversary.example  Denied
  did:opena2a:authority:enterprise.acme    Conditional (max trust level 2)
```

A UK verifier checking an ATX issued by gov.us looks up gov.us in the local trust list. Allowed. Cosignature path established. Verification proceeds.

A UK verifier checking an ATX issued by an authority not on the list falls back to the cross org cosigning protocol. The root node (OpenA2A) may be queried for a neutral cosignature. If the UK trust list does not recognize the root node either, verification fails closed.

### 3.3 Bilateral trust agreements

Two sovereigns recognizing each other's ATX is a bilateral agreement. The architecture provides the protocol mechanism. The agreement itself is a policy and legal artifact.

A bilateral agreement typically specifies:

* The DIDs each side publishes and the keys those DIDs resolve to.
* The trust level mapping (how each side's level 3 maps to the other's).
* The revocation propagation requirements (how fast a revocation on one side must propagate to the other).
* The dispute resolution mechanism if one side refuses to honor a revocation.
* The conditions under which the agreement terminates.

The protocol mechanism is: add the counterparty to the trust list, publish a cosignature endpoint that accepts requests from the counterparty, exchange public key material via a signed channel.

### 3.4 Trust list publication

Each sovereign publishes its trust list at a well known sovereign URL. The list itself is signed by the sovereign's keys. Verifiers within the jurisdiction download and cache the trust list (TTL 24 hours, or push on update).

Publishing the trust list openly is not a sovereignty violation. It is a transparency property. Other sovereigns can see who recognizes whom. Diplomatic and trade decisions can be informed by the actual structure of recognition.

### 3.5 What about classified relationships?

For relationships that cannot be public, the sovereign maintains a private trust list visible only within its perimeter. The public trust list shows the publicly recognized relationships. The private trust list is enforced internally and never published.

This pattern is required for intelligence sharing relationships, classified industrial partnerships, and any bilateral relationship that cannot be acknowledged publicly. The protocol supports it because the trust list is sovereign controlled. The public and private layers are sovereign managed and never visible to OpenA2A or any other external party.

---

## 4. Cross border cosigning

When a credential issued in one jurisdiction needs to be honored in another, the cosignature mechanism is what bridges them. This is the most architecturally delicate part of the system.

### 4.1 The bilateral path

Two recognized sovereigns:

1. Agent A in jurisdiction X holds an ATX issued by gov.x.
2. Agent A calls a service in jurisdiction Y.
3. Verifier in Y looks up did:opena2a:authority:gov.x in Y's trust list. Allowed.
4. Verifier in Y has gov.x's public key cached. Signature verifies.
5. ATX accepted at its specified trust level (potentially capped per Y's policy).

No external arbiter is involved. The two sovereigns have a bilateral agreement. The cryptographic verification confirms the agreement is being honored.

### 4.2 The mediated path

Two sovereigns with no direct bilateral but both recognizing the root:

1. Agent A in jurisdiction X holds an ATX issued by gov.x.
2. Agent A calls a service in jurisdiction Y.
3. Verifier in Y looks up gov.x. Not on local trust list.
4. Verifier requests a cosignature from the root authority (did:opena2a:authority:opena2a.org).
5. Root verifies the gov.x signature, checks that gov.x is on the root's trust list, issues a cosignature.
6. Cosigned ATX has issuerChain = [gov.x, opena2a.org]. Verifier in Y accepts the credential because Y trusts the root.

The root acts as a neutral cosigner. This is exactly the role Verisign plays for cross CA TLS in WebPKI today. The root does not vouch for the agent. It vouches that the issuing authority is a recognized member of the federation.

### 4.3 The deny path

Two sovereigns with a hostile relationship:

1. Agent A in adversary jurisdiction holds an ATX issued by adversary.gov.
2. Agent A attempts to call a service in jurisdiction Y.
3. Verifier in Y looks up adversary.gov. Denied.
4. Verification fails immediately. No fallback. No mediation attempt.

The credential may be cryptographically valid. The signature may verify. The transparency log may show the issuance is real. None of that matters. The trust list is the gate, and the trust list says no.

### 4.4 Trust level downgrade across borders

A common pattern: honor the credential but cap the trust level when it comes from outside the jurisdiction.

Example: UK sovereign accepts US sovereign ATX at full trust level for read operations and capped trust level for write operations. The conditional state in the trust list encodes this. The credential is honored. The capabilities the credential authorizes are constrained at the verifier.

This is the mechanism that lets a sovereign say: I trust you, but not as much as I trust myself. It is a generalization of the "external" versus "internal" boundary that most enterprises already enforce informally.

---

## 5. Data residency and jurisdiction binding

Every byte of credential metadata has a defined residency. The architecture is explicit about what stays where.

### 5.1 What lives inside the sovereign perimeter

* **Build attestations.** The full attestation body, including commit hashes, builder identity, and CI run metadata.
* **Scan results.** Detailed HMA, Secretless, CryptoServe scan outputs.
* **Behavioral profiles.** L1 baseline data, behavioral twin checksums, anomaly events.
* **Agent identity records.** Full OpenA2A AIM (Agent Identity Management) keypair history, capability grants, trust factor breakdowns.
* **Transparency log entries.** The sovereign's own log, which references but does not duplicate other sovereigns' logs.
* **CRL entries.** All revocations issued by the sovereign.

### 5.2 What can be shared and what cannot

| Data | Sharing default | Sovereign override |
|---|---|---|
| ATX credential body (hash, signatures, public fields) | Shared (travels with the agent) | Can be marked sovereign only for classified agents |
| Build attestation body | Sovereign only | Can be selectively shared with cosigning party |
| Scan result detail | Sovereign only | Summary fields are shared in the ATX scanSummary |
| Behavioral profile detail | Sovereign only | Checksum is shared in the ATX behavioralProfile |
| Transparency log entries | STH and inclusion proofs are public; full entries may be sovereign only | Sovereign decides per entry type |
| CRL entries | Public by default (revocation is public information) | Sovereign can mark a revocation as "details classified" while still publishing the revocation |

The pattern: signatures and verification anchors are public. Full underlying data is sovereign controlled. A verifier outside the jurisdiction can confirm "this ATX was validly issued and is not revoked" without seeing the sovereign's internal data.

### 5.3 Jurisdiction binding at issuance time

Every ATX issued by a sovereign node includes the sovereign's DID in issuerDid. This is the jurisdiction binding. A regulator examining an agent's credentials can read the DID and know which jurisdiction's law applies to the issuance.

The agent identity itself (agentDid) may belong to an enterprise that operates across multiple jurisdictions. The ATX issuer establishes which sovereign issued this specific credential. An enterprise with operations in three jurisdictions may have three different ATX credentials for the same agent identity, one per jurisdiction, each issued by the local sovereign node.

---

## 6. Air gapped operation

For classified networks, intelligence agencies, and any environment with no internet connectivity, the sovereign node operates entirely offline.

### 6.1 What works without internet

* Issuance, verification, revocation, transparency logging within the air gapped network all function normally.
* Local CRL distribution continues.
* Local DID document service continues.
* Federation gateway is configured to expect no inbound or outbound traffic.

### 6.2 What requires periodic synchronization

* **STH publication to the external world.** The air gapped sovereign publishes STH via one way egress (a data diode or manual export). External parties can verify the air gapped sovereign's transparency log without ever connecting to it.
* **CRL updates from external sovereigns.** If the air gapped sovereign maintains a trust list that includes external parties, their CRLs must be imported periodically. One way ingress via signed CRL files on physical media or a data diode.
* **Cross border cosignatures.** Cannot happen in real time. Either pre signed batches (the external sovereign cosigns a batch of credentials that the air gapped sovereign will need) or no cross border interactions at all.

### 6.3 Sneakernet CRL distribution

A sovereign can publish its CRL as a signed file. Physical media (USB stick, classified courier) carries the file across the air gap. The receiving sovereign imports the file, verifies the signature against the cached DID document, updates its local CRL state.

Latency is hours to days, not seconds. This is acceptable for sovereign to sovereign revocation propagation in classified contexts. Within the air gapped sovereign's own population, revocation propagates in normal (sub 60 second) time.

### 6.4 One way egress for transparency

The transparency log is the most important artifact to share externally even from an air gapped environment. STH publication is small (under 1 KB per 5 minutes), can be exported via a data diode, and provides external accountability without compromising the air gap.

This is the same pattern intelligence community CT logs already use for monitoring purposes.

---

## 7. Reconciliation with the global transparency log

Sovereign nodes maintain their own transparency logs. They do not write to OpenA2A's log. But the global view requires some level of coordination.

### 7.1 Mirror nodes

OpenA2A (or any recognized observer) can run a mirror node that subscribes to the sovereign's published STHs and verifies them against the sovereign's transparency log via inclusion proofs. The mirror does not have write access. The mirror provides an external accountability check.

Mirror nodes can be operated by:

* OpenA2A itself (for sovereigns that opt in)
* Other sovereigns (bilateral arrangement)
* Standards bodies (IETF, ISO, NIST as appropriate)
* Independent researchers and security firms

The sovereign decides who can mirror. The mirror cannot tamper with the log. The mirror can detect tampering and publish alerts.

### 7.2 Independent verifiability without dependency

A verifier can verify a sovereign issued ATX without ever contacting the sovereign or OpenA2A:

1. The ATX includes the transparency log index and STH that contains it.
2. The verifier holds the sovereign's published DID document (cached) and a recent STH (cached).
3. The verifier reconstructs the inclusion proof locally from cached data.

If the verifier wants to confirm against a more recent STH, the STH stream is a 1 KB per 5 minute feed that any mirror serves. No live query to the sovereign is required.

---

## 8. Compliance posture

The sovereign architecture is designed to map cleanly to existing regulatory regimes. The credential format itself is the compliance artifact.

### 8.1 EU AI Act

The Act distinguishes high risk, limited risk, and minimal risk AI systems. ATX trust level and scan summary map directly to the regulator's evidence requirements.

| EU AI Act requirement | ATX evidence |
|---|---|
| Risk management system | OASB compliance level embedded in scanSummary |
| Data and data governance | Build attestation includes data source declarations |
| Technical documentation | The ATX itself is technical documentation, signed and timestamped |
| Record keeping | Transparency log provides immutable record |
| Human oversight | AIM capability grants in the ATX show human authorized capabilities |
| Accuracy, robustness, cybersecurity | HMA scan results in scanSummary |

A sovereign node operated by an EU member state issues ATX that is automatically EU AI Act compliant evidence.

### 8.2 NIST AI RMF

The Risk Management Framework's four functions (Govern, Map, Measure, Manage) map to ATX:

* **Govern.** Sovereign trust list and federation policy.
* **Map.** ATX capabilities field plus AIM identity bindings.
* **Measure.** Scan summary plus behavioral profile.
* **Manage.** Revocation and reissuance lifecycle.

### 8.3 FedRAMP and sovereign cloud

For US federal civilian use, a sovereign node operates within a FedRAMP authorized environment. The node's keys are in a FedRAMP HSM. The transparency log resides in FedRAMP storage. The federation gateway is the only external interface and is subject to FedRAMP boundary protection.

For US DoD, the same pattern applies with IL5 or IL6 controls depending on classification level. Air gapped operation is the default for IL6.

### 8.4 GDPR and data protection

ATX does not embed personally identifiable information by default. The credential identifies an agent, not a human. Where human identity is relevant (the developer who authored the build, the operator who approved a capability grant), those references are kept in the sovereign's internal records and not in the credential body that travels with the agent.

The credential itself can be shared across borders without GDPR concerns. The full build attestation that backs the credential stays within the sovereign perimeter and is governed by local data protection law.

---

## 9. Deployment scenarios

The architecture maps to real world deployment patterns.

### 9.1 US federal civilian agency

* Single sovereign node operated by GSA or a contracted FedRAMP authorized provider.
* Trust list includes OpenA2A root, allied sovereign nodes (UK, Canada, Australia, New Zealand), other US federal sovereign nodes (DoD, intelligence community as appropriate).
* All federal AI agents issued ATX by this node.
* External agents calling into federal systems present their ATX; the federal verifier honors based on trust list.

### 9.2 US DoD classified network

* Air gapped sovereign node operated within the classified enclave.
* No federation gateway to the public internet.
* Trust list includes only classified peers.
* STH egress via data diode for external accountability.
* Internal operation is fully functional including issuance, verification, revocation.

### 9.3 EU member state national node

* Sovereign node operated by the national digital agency.
* Trust list includes EU central node, fellow member state nodes, and the OpenA2A root.
* Cross border cosignatures within the EU are bilateral, not mediated.
* Compliance evidence per EU AI Act is automatic via the ATX format.

### 9.4 Allied nation with restricted relationships

* Sovereign node with full ATP capability.
* Trust list includes OpenA2A root and a subset of allies.
* Specifically denies authorities from adversary nations.
* Recognizes some authorities at full trust, others at conditional trust capped to read only operations.

### 9.5 Regulated industry consortium

* Healthcare provider consortium operates a shared sovereign node for member organizations.
* Trust list includes OpenA2A root and member specific enterprise nodes.
* Compliance evidence per HIPAA and EU AI Act is automatic via the ATX format.
* Members can issue ATX for their own agents while sharing the underlying federation infrastructure.

---

## 10. Revocation under sovereignty

Revocation is the most politically sensitive operation in the federation. Who can revoke whose ATX, and how does the propagation work when relationships are hostile?

### 10.1 Who can revoke

| Revocation target | Who can revoke |
|---|---|
| ATX issued by sovereign X for an agent in X's jurisdiction | Sovereign X only |
| Recognition of sovereign Y's authority (within X's trust list) | Sovereign X (by updating its trust list) |
| Federation cosignature issued by sovereign X | Sovereign X (publishes a revocation entry in its log) |
| OpenA2A root cosignature | OpenA2A root (transparency logged and broadly visible) |

No sovereign can revoke another sovereign's ATX. The most a sovereign can do is remove that authority from its own trust list, which causes credentials from that authority to fail verification within this sovereign's jurisdiction.

### 10.2 Cross border revocation propagation

When sovereign X revokes an ATX, sovereigns Y and Z that have X on their trust lists need to learn about the revocation. The architecture provides:

* Federation push from X's CRL endpoint to recognized peers (under 60 seconds).
* SSE subscription for verifiers that want immediate notification.
* Periodic CRL pull (every 5 minutes default) as the fallback.
* Sneakernet CRL distribution for air gapped peers (hours to days).

The receiving sovereign decides how to handle the revocation. Default is to honor it, since they recognize X as an authority. Some sovereigns may delay or refuse propagation in specific cases. This is a policy decision, not an architectural one.

### 10.3 Hostile relationship handling

If sovereign X starts issuing fraudulent ATX (compromised keys, malicious actor, regime change), other sovereigns have a defined response:

1. Update local trust list. Move X from Allowed to Denied.
2. Publish the change. Verifiers in this sovereign's jurisdiction stop honoring X's credentials immediately.
3. Notify the OpenA2A root, which may remove X from the root's trust list.
4. If X was a recognized member of a multi sovereign consortium, the consortium decides whether to expel X.

The protocol provides the mechanism. The decision is political. The transparency log makes the decision visible. The cryptographic verifications continue to be honored or rejected per the updated trust list state.

---

## 11. The sovereign onboarding checklist

What a sovereign needs to do to stand up an ATP node and join the federation.

### Pre deployment

1. Define jurisdiction and scope. Which agents and publishers will this node issue for?
2. Provision HSM infrastructure. Threshold signing, sovereign controlled.
3. Generate sovereign authority keys. Publish DID document at sovereign controlled URL.
4. Decide hosting. Sovereign cloud, dedicated data center, air gapped enclave.
5. Define initial trust list. Which authorities will this sovereign recognize on day one?

### Deployment

6. Stand up issuing node, transparency log, CRL service, DID document service, federation gateway, monitor.
7. Configure threshold signing across HSMs.
8. Publish DID document and STH stream.
9. Run synthetic load to validate capacity targets.

### Federation

10. For each authority on the trust list, exchange DID documents and public key material. Validate signature against published key.
11. For each recognized authority, configure federation push subscriptions.
12. Submit DID document to OpenA2A root (if root recognition is desired) for inclusion in the root's trust list.
13. Publish trust list at the sovereign controlled URL.

### Operations

14. Monitor STH cadence. Alert on gaps greater than 10 minutes.
15. Monitor CRL propagation latency to peer nodes.
16. Run external monitor instances or invite external parties to monitor.
17. Define and publish revocation policy (what triggers a revocation, how fast it propagates).
18. Define and publish bilateral cosigning policy for each recognized authority.

### Compliance evidence

19. Document the deployment against EU AI Act, NIST AI RMF, FedRAMP, or applicable national framework.
20. Provide auditor access to the transparency log and inclusion proof tooling.
21. Publish the sovereign's compliance posture (which frameworks the node satisfies).

A sovereign that completes this checklist is a fully functional ATP authority. It can issue ATX for its population, federate selectively with the rest of the ecosystem, and operate independently of OpenA2A or any other vendor.

---

## 12. The architectural promise

The promise this architecture makes to a sovereign:

1. You will never be in a federation you did not choose.
2. You will never be excluded from a federation you want to join, unless other members refuse to recognize you.
3. Your credentials will be honored everywhere your trust list is honored, and nowhere it is not.
4. Your data stays within your jurisdiction unless you choose to share it.
5. Your keys are yours. No external party can sign on your behalf.
6. Your trust list is yours. No external party can force you to add or remove authorities.
7. Your decisions are auditable. The transparency log is the immutable record.
8. Your sovereignty extends to disconnect. You can operate air gapped if you choose.

The architecture makes these eight promises operationally enforceable, not just rhetorically asserted. That is what makes ATP a candidate to become sovereign AI trust infrastructure at the national and international level. No other AI agent trust system today can make these promises and back them with cryptographic enforcement. That is the wedge.

---

*ATX sovereign federation architecture v1.0. May 2026. OpenA2A. Companion to the ATX core architecture and ATX scalability architecture docs.*
