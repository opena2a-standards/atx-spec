# Use cases: reference detail

Text that the use cases in the [README](../README.md) link to, kept here in full.

## The agent you approved last week is not the one acting now

Where it stops today: a verifier whose cached revocation list is more than five minutes old refreshes it in the background and still allows the current request on the stale list. The `fixtures/revoked.json` credential also carries `revoked: true`, a field outside the signed bytes, so a verifier that never reads the revocation list still rejects it; `fixtures/revoked-crl-only.json` carries `revoked: false` with its agent on the verifier's list, so that verifier wrongly accepts it. No fixture exercises the five-minute bound or a request served on a stale list.
