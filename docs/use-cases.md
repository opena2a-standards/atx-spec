# Use cases: reference detail

Text moved out of the [README](../README.md), kept here in full: the summary that opened it, and the detail its use cases link to.

## What ATX is

ATX is a signed, self-contained credential carried by every AI agent. It is analogous to a TLS certificate but contains agent identity, scan results, capabilities, and behavioral profile. Local verification under 5ms. Ed25519 + ML-DSA-65 hybrid signatures mandatory at v1.

## The agent you approved last week is not the one acting now

Where it stops today: a verifier whose cached revocation list is more than five minutes old refreshes it in the background and still allows the current request on the stale list. The `fixtures/revoked.json` credential also carries `revoked: true`, a field outside the signed bytes, so a verifier that never reads the revocation list still rejects it; `fixtures/revoked-crl-only.json` carries `revoked: false` with its agent on the verifier's list, so that verifier wrongly accepts it. No fixture exercises the five-minute bound or a request served on a stale list.
