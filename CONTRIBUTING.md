# Contributing to ATX

The Agent Trust eXtension credential format is authored in the open and published with a working reference implementation, OpenA2A AIM (Agent Identity Management), and a byte-stable conformance suite. It is early, and we are looking for co-authors and contributors to help shape it before it goes to an external standards body. Your review, critique, and independent implementation work all carry weight on the spec.

## What we are looking for

- Review and critique. Read [core.md](core.md), [scalability.md](scalability.md), and [sovereign-federation.md](sovereign-federation.md) and tell us where they are ambiguous, where they leave interoperability gaps, or where the local-verify algorithm does not hold up.
- An independent second implementation. A non-AIM implementation of ATX issuance or verification is the strongest signal that the spec is sound. Tested against the conformance fixtures, it is the gold standard for proving the format.
- Security audit and threat modeling of the spec itself, not just an implementation.
- Cryptography and signatures expertise. ATX mandates a hybrid Ed25519 plus ML-DSA-65 signature at v1. We want input from people who have implemented post-quantum signatures, canonicalization, and revocation, and who can find weaknesses in the signing and verification model.
- We need a second independent verifier. Our own local-verification libraries are reference implementations, not independent ones: the TypeScript verifier ships in [`@opena2a/aim-sdk`](https://www.npmjs.com/package/@opena2a/aim-sdk), and the Java verifier is in the AIM tree but is not yet published to Maven Central. We also want cryptography review of the Ed25519 and hybrid ML-DSA-65 signing.

## Who we are looking for

We especially welcome:

- Security and cryptography researchers, including academic and PhD-level work.
- Standards-process experts (W3C, IETF, OpenTelemetry) who can help take these specifications to external bodies.
- Engineers building agent platforms and runtimes, for independent implementations and adoption.
- Red teamers and security auditors.

## How to contribute

- Open an issue or pull request on this repository.
- Or email info@opena2a.org with "co-author" in the subject line.
- For cryptographic findings, signature weaknesses, or coordinated disclosure, email info@opena2a.org or info@opena2a.org.

Small fixes (typos, broken links, clarifications) can go straight to a pull request. For anything that changes the credential format, signature suite, or verification algorithm, open an issue first so the change can be discussed before implementation work begins.

## Ground rules

- Contributions are licensed under Apache-2.0, consistent with the project license.
- Be specific and evidence-based. Point to the section, the field, or the failing case.
- No purely theoretical claims without a path to validation. If you propose a change, describe how it could be tested against the conformance suite or implemented.
