# ATX scalability architecture

**How the system scales to a billion agents**

Version 1.0. May 2026. This document is the scalability companion to the ATX core architecture. It explains why the credential model scales, where the bottlenecks are, what the failure modes look like, and what is intentionally not scaled.

The credential model is what made TLS work at planetary scale. The same properties carry over to ATX. This document makes those properties explicit and operationally measurable.

---

## 1. Scalability at a glance

The summary in one paragraph: verification is local, issuance is bounded by build rate, the transparency log is logarithmic, the revocation list is delta synced, and federation isolates load by jurisdiction. The system has no global hot path. There is no single coordinator that has to handle every agent interaction. The properties below explain why each of those claims holds.

| Concern | Limit | Scaling property | Headroom |
|---|---|---|---|
| Verification throughput | Per verifier CPU | O(1) per check, no network calls in warm cache | Limited by the verifier's host, not the network |
| Issuance throughput | Build rate of issuing node | Bounded by builds per second, not agents | Issuing nodes provisioned to peak build rate plus 5x |
| Webhook ingestion | Two global feeds | O(1) on package count | 1.1M packages today, 1B is the same shape |
| Transparency log | Append only | O(log n) inclusion proofs | A 10M entry log verifies in 23 hashes |
| CRL distribution | Federated push plus CDN cache | Delta sync, 5 minute TTL | Single CRL serves all verifiers via CDN |
| Storage | 7 day ATX expiry | Active set stays bounded | Archive on cold storage, never on hot path |
| Federation | Bilateral cosignatures | Load isolated by node | Each node sized for its own population |

The numbers are not aspirations. They are direct consequences of the architectural commitments in the core doc.

---

## 2. The O(1) verification invariant

Verification is the operation that happens at the highest frequency. Every agent to agent call, every agent to MCP server call, every MCP server to tool call requires a verification. At a billion agents making one call per second on average, that is a billion verifications per second across the ecosystem.

The architecture handles this volume because no single party has to handle it. Verification is distributed across every verifier in the network. The cost per verifier scales with the verifier's own request volume, not with the size of the ecosystem.

### 2.1 What verification actually costs

Warm cache verification, broken down:

| Step | Cost | Notes |
|---|---|---|
| Parse ATX JSON | 0.05 ms | Bounded by JSON length, typically 1 to 4 KB |
| Expiry check | 0.001 ms | Single comparison |
| DID document cache lookup | 0.01 ms | In memory hash map |
| Ed25519 signature verify | 0.4 ms | Constant time |
| ML-DSA-65 signature verify | 3 ms | Constant time, optional path |
| CRL cache lookup | 0.05 ms | In memory hash map |
| Content hash compare (optional) | 0.1 ms | SHA-256 of presented artifact |
| Total warm cache | 1 to 4 ms | Dominated by signature verification |

Cold cache adds one DID document fetch and one CRL refresh. Both are one time costs amortized across thousands of subsequent verifications. Cold start is under 50 ms total. After that, every verification reverts to warm cache cost.

### 2.2 Why this matters for global scale

A modest verifier (4 vCPU, no hardware acceleration) handles approximately 1,000 verifications per second per core. Four cores yields 4,000 verifications per second. The ecosystem reaches a billion verifications per second when there are 250,000 such verifiers running. That number is dwarfed by the agent population that would generate that load in the first place.

The math is the point. Verification scales linearly with the verifier population. The verifier population scales linearly with the agent population. There is no bottleneck anywhere in this chain.

---

## 3. Asymmetric workload: issuance versus verification

The system has two very different workloads.

**Issuance** happens once per build. A build takes 30 to 90 seconds. The output is one ATX. At scale, the issuance rate is bounded by how often code is built and shipped. For a population of one billion agents, even if every agent rebuilds weekly, that is approximately 1,650 issuances per second globally. Distributed across federation, no single node handles more than a few hundred per second.

**Verification** happens on every agent interaction. For a billion agents at one call per second, that is a billion verifications per second.

The ratio is roughly 600,000 to 1. The architecture matches this asymmetry: issuance is centralized at the issuing node level for cryptographic integrity. Verification is distributed across every verifier with zero coordination.

| Workload | Rate | Where it runs | Scaling concern |
|---|---|---|---|
| Issuance | Bounded by build rate | Issuing nodes (centralized per tenant) | Capacity plan per node, mostly database IOPS |
| Verification | Bounded by interaction rate | Every verifier (fully distributed) | None at the architectural level |

Provisioning for issuance is straightforward. Each issuing node sizes for its tenant population's build rate. Verification provisioning is the verifier's own concern. There is no shared capacity to allocate.

---

## 4. Webhook scalability: two feeds, not a million

The prior model had a webhook subscription per package. At 1.1 million packages, that meant 1.1 million subscriptions to register, renew, monitor, and reconcile. Operationally infeasible.

The new model uses two global subscriptions, independent of package count:

* One npm registry level webhook feed. Receives all npm publish, unpublish, and dist tag changes globally.
* One GitHub org level webhook. Receives all push and tag events for repositories linked to ATP publishers.

For each event received, the issuing node asks one question: does a valid ATX exist for this content hash?

That question is a single database lookup against an indexed column. Sub millisecond regardless of whether the registry contains 1 million packages or 1 billion.

### 4.1 Event volume estimates

npm processes approximately 30 publish events per second at peak. GitHub processes approximately 1,000 push events per second across all repositories. If every npm package and every GitHub repository were ATP linked, peak event volume would be roughly 1,000 events per second to process. Each event is a single indexed lookup plus a possible CRL update.

A single Postgres instance handles 100,000 indexed lookups per second easily. The webhook feed could grow 100x and still fit on a single database. The architecture has more than three orders of magnitude of headroom on this dimension.

### 4.2 Why this works

The trick is that we are not tracking subscriptions to packages. We are subscribing to the entire registry once and filtering server side. The cost of the feed is fixed. The cost of filtering scales with event volume, not package count. Event volume scales with how often code is built, not how many packages exist.

This is the same trick that makes RSS aggregation feasible. One feed per source, not one subscription per article.

---

## 5. Transparency log scaling

The transparency log grows monotonically. Every ATX issuance, every revocation, every key rotation adds an entry. At a billion agents reissuing weekly, the log adds roughly 1,650 entries per second on average and peaks higher during CI rush hours.

### 5.1 Why O(log n) matters

Inclusion proof cost is O(log n). The math:

| Log size | Inclusion proof | Storage of proof |
|---|---|---|
| 1,000 | 10 hashes | 320 bytes |
| 1,000,000 | 20 hashes | 640 bytes |
| 1,000,000,000 | 30 hashes | 960 bytes |
| 1,000,000,000,000 | 40 hashes | 1,280 bytes |

A trillion entry log produces a proof that fits in a single TCP packet. Verification is constant time SHA-256 hashing. An auditor can verify any single ATX issuance in milliseconds without downloading the rest of the log.

Sequential hash chaining (the old approach) requires verifying the entire chain to detect tampering. At a trillion entries that becomes infeasible. RFC 6962 binary Merkle tree is what makes external verification practical at planetary scale.

### 5.2 STH publication cadence

Signed Tree Heads publish every 5 minutes. At 1,650 entries per second, that is roughly 500,000 entries between STH publications. The STH itself is small (under 1 KB) and can be served from a CDN.

Monitors verify the consistency proof between consecutive STHs. The consistency proof is also O(log n) in the log size. A monitor running every 5 minutes downloads under 2 KB per cycle to verify the log has not been tampered with.

### 5.3 Storage of the log itself

A trillion entry log at 256 bytes per entry is 256 TB. That is large but not unmanageable. Hot storage holds the most recent month (roughly 4 TB at the projected rate). Older entries move to object storage where retrieval is slow but cheap.

External monitors do not need the full log. They need the STH stream plus inclusion proofs on demand. The full log lives at the issuing node. Other parties query it as needed.

---

## 6. CRL distribution at scale

The Certificate Revocation List is the only dynamic data verifiers need to fetch. The cache and distribution model is designed to make this cheap.

### 6.1 Push then pull

When a revocation happens, the issuing node:

1. Pushes a delta CRL to all subscribed federation nodes via HMAC signed HTTP POST. Target: under 5 seconds.
2. Publishes the updated full CRL to the public endpoint. CDN cache invalidated.
3. Emits an SSE event for the affected agentId on the trust_changed channel.

Verifiers consume the CRL in one of three modes:

| Mode | Latency to revocation | Network cost |
|---|---|---|
| Cached pull, 5 minute TTL | Up to 5 minutes | Single GET every 5 minutes |
| Pull plus SSE subscription | Under 60 seconds | Single GET every 5 minutes plus persistent SSE connection |
| Federation push subscriber | Under 30 seconds | Active push from the issuing node |

The 5 minute TTL is the hard upper bound. Verifiers that need faster revocation handle subscribe to the SSE stream or join the federation push tier.

### 6.2 CRL size

A full CRL listing every revoked agentId is small. Each entry is roughly 40 bytes (agentId plus revocation timestamp plus reason code). One million revocations is 40 MB. Compressed and CDN cached, a single CRL serves the entire ecosystem.

Delta CRLs are much smaller. A delta from STH N to STH N+1 covers approximately 5 minutes of revocations, typically a few KB.

### 6.3 Cache hierarchy

Verifiers cache the CRL locally. The issuing node serves the CRL from a CDN. Federation nodes mirror the CRL within their jurisdictions. The hierarchy:

```
Issuing node (canonical)
  -> CDN edge nodes (read replicas, 1 minute origin TTL)
    -> Federation nodes (mirror plus push subscriber)
      -> Verifiers (local cache, 5 minute TTL)
```

A verifier that loses network access continues using its cached CRL until the cache expires. The cache is signed, so a stale CRL cannot be tampered with. The verifier still rejects revoked credentials that were on the CRL when the cache was last refreshed.

---

## 7. Federation topology and load isolation

Federation is not just a sovereignty feature. It is also a scaling mechanism. Each federation node serves its own population. Cross node interactions add bilateral cost, but most interactions stay within a single node's scope.

### 7.1 Load distribution

In a mature federation:

* Each enterprise node handles its own agents' build attestations and ATX issuance.
* Each sovereign node handles its jurisdiction's agents.
* The root node (OpenA2A) handles community packages and cross node cosignatures.

The root node's load is bounded by the rate of cross node trust level 4 requests, not the total agent population. If 1 percent of interactions require root cosignature, the root node handles 1 percent of the global verification load. The other 99 percent is fully local.

### 7.2 Why federation improves scalability

Naive intuition says federation adds coordination overhead. The opposite is true at scale.

* **No single party is sized for global load.** Each node is sized for its own population.
* **Latency is local.** A US sovereign node serves US verifiers from US data centers.
* **Failures are isolated.** A node going down affects only its own population.
* **Updates are decoupled.** Each node updates its software on its own cadence.

The cost of federation is the bilateral cosignature for cross node interactions. The cosignature is one Ed25519 signature plus one DID document lookup. Sub 5 ms. Compared to a database query that fans out across the entire ecosystem, federation is cheaper at every meaningful scale.

---

## 8. Storage scaling

The 7 day ATX expiry is doing a lot of work for scalability. The active credential set stays bounded even as the historical population grows.

### 8.1 Active versus historical

* **Active ATX.** Every currently valid credential. Refreshed weekly. At a billion agents reissuing weekly, the active set is roughly 1 billion ATX, each averaging 2 KB. That is 2 TB of hot storage.
* **Historical ATX.** Every expired credential ever issued. Useful for audit and compliance. Stored in object storage. Retrieved on demand. Cold path only.

The transparency log keeps a record of every issuance. Historical ATX bodies can be reconstructed from the log plus the database snapshot at any STH. The hot path does not need to keep them.

### 8.2 Database sizing per node

A mature enterprise node serving 100,000 agents handles:

* 100,000 active ATX at 2 KB each = 200 MB
* Weekly reissuance: 100,000 build attestations per week = ~150 KB per second peak
* Transparency log local mirror: ~10 GB per year

Even a billion agent node fits comfortably on commodity infrastructure. The architecture does not assume exotic database technology.

---

## 9. Failure mode behavior: Zero Failures in action

Scalability includes how the system behaves when components fail. Zero Failures is the architectural commitment that no OpenA2A service is on the critical path of customer operations.

### 9.1 Issuing node down

* **Verification:** unaffected. Verifiers use cached DID documents and CRLs. Verification continues at full throughput.
* **Issuance:** new builds queue locally. The build plugin uses a 30 day delegated signing certificate to mint ATX locally during outage. The local ATX uploads to the issuing node when it recovers. Asynchronous reconciliation.
* **Revocation:** new revocations queue. Existing CRL continues to serve from CDN. New CRL deltas publish when the issuing node recovers.
* **Transparency log:** new entries queue locally. Hash chain integrity is preserved on reconciliation. Monitors flag the gap but the gap is signed and explainable.

### 9.2 Federation node partition

* The partitioned node continues operating for its local population. Issuance, verification, and revocation all work.
* Cross node cosignatures for the partitioned node degrade to "unverified by root" until the partition heals. Trust level 4 requests fall back to trust level 3.
* When the partition heals, the partitioned node syncs its transparency log entries to the root node and the global view becomes consistent again.

### 9.3 Transparency log degraded

* Issuance can continue at reduced trust level if the log cannot accept new entries. Issued ATX is marked as "log pending" and upgrades to fully attested once the log recovers.
* Monitors alert on log unavailability. The protocol forces transparency: if the log is down, every participant knows.
* No silent degradation. The credential includes the transparency log index. A missing index is detectable.

### 9.4 Whole region failure

* Federation nodes in other regions continue serving their populations.
* Verification globally continues using cached state.
* The failed region's traffic does not fail over to other regions, because each region is sovereign over its own ATX. Cross region traffic degrades to "untrusted" until the region recovers, but verification of intra region traffic continues normally.

The system never has a global brownout. The worst case is that a specific node's customers lose ability to mint new ATX for a while. Their existing ATX continues to verify. Their agents keep running.

---

## 10. Capacity targets

Hard numbers per node tier. These are the minimum capacities a node must support to claim ATP conformance.

| Node tier | Active ATX | Issuance rate | Verification rate (local) | Hardware |
|---|---|---|---|---|
| Root | 10M (community packages) | 100 per second peak | 100,000 per second | 16 vCPU, 64 GB RAM, 1 TB SSD |
| Enterprise (large) | 1M agents | 50 per second peak | 50,000 per second | 8 vCPU, 32 GB RAM, 500 GB SSD |
| Enterprise (mid) | 100K agents | 10 per second peak | 10,000 per second | 4 vCPU, 16 GB RAM, 200 GB SSD |
| Sovereign | 100K agents | 10 per second peak | 10,000 per second | Tenant defined, often air gapped |
| Community | 10K packages | 5 per second peak | 1,000 per second | 2 vCPU, 8 GB RAM, 50 GB SSD |

The verification rate is what the node serves to direct API consumers (CRL fetches, DID document lookups). The actual verification rate in the ecosystem is much higher, because verifiers run locally everywhere.

---

## 11. What does not scale (and why that is fine)

A few operations intentionally do not scale to a billion agents because they do not have to.

* **Manual root key rotation.** This happens rarely (yearly) and requires coordinated ceremony. Not in any critical path.
* **Federation node onboarding.** Bilateral agreement, trust list configuration, public key exchange. Hours to days per node. Done once per relationship.
* **CNA assignment.** Done at sovereign or enterprise level for that population. Not per agent.
* **Cross border legal agreements.** This is the sovereignty layer, not the architecture layer. The protocol can run faster than the lawyers.
* **Threat Matrix updates.** Done by humans plus OpenA2A's automated threat research. Not per credential. Updates flow through transparency log entries that monitor the taxonomy itself.

The architecture is deliberately minimal in what it requires to scale. Anything that does not need to be O(1) is left as O(humans).

---

## 12. The asymmetry that makes it work

The deepest property of the system: the cost of issuance is borne by the issuer, the cost of verification is borne by the verifier, and there is no global coordinator that bears any cost on every interaction. This is the only model that scales to a billion agents because no participant ever has to handle more load than their own slice of the ecosystem produces.

TLS works for the same reason. ATX is the same architecture for a new asset class.

---

*ATX scalability architecture v1.0. May 2026. OpenA2A. Companion to the ATX core architecture doc.*
