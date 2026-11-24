# Contributing to ATX

The Agent Trust eXtension credential format is authored in the open and published with a byte-stable conformance suite and reference verifiers. OpenA2A's issuing node is the OpenA2A Registry service, and OpenA2A AIM (Agent Identity Management) verifies ATX and does not issue it. The format is early, and we are looking for co-authors and contributors to help shape it before it goes to an external standards body. Your review, critique, and independent implementation work all carry weight on the spec.

## What we are looking for

- Review and critique. Read [core.md](core.md), [scalability.md](scalability.md), and [sovereign-federation.md](sovereign-federation.md) and tell us where they are ambiguous, where they leave interoperability gaps, or where the local-verify algorithm does not hold up.
- An independent second implementation. An implementation of ATX issuance or verification written outside OpenA2A, tested against the conformance fixtures, shows whether people who did not write the specification can implement it from the text.
- Security audit and threat modeling of the spec itself, not just an implementation.
- Cryptography and signatures expertise. ATX mandates a hybrid Ed25519 plus ML-DSA-65 signature at v1. We want input from people who have implemented post-quantum signatures, canonicalization, and revocation, and who can find weaknesses in the signing and verification model.
- We need a second independent verifier. Our own local-verification libraries are reference implementations, not independent ones: the TypeScript verifier is [`@opena2a/atx-verify`](https://github.com/opena2a-org/opena2a/tree/main/packages/atx-verify), which `@opena2a/aim-sdk` depends on, and the Java verifier is in the AIM repository at [`sdk/java`](https://github.com/opena2a-org/agent-identity-management/tree/main/sdk/java) and is not published to Maven Central. We also want cryptography review of the Ed25519 and hybrid ML-DSA-65 signing.

## Who we are looking for

We especially welcome:

- Security and cryptography researchers, including academic and PhD-level work.
- Standards-process experts (W3C, IETF, OpenTelemetry) who can help take these specifications to external bodies.
- Engineers building agent platforms and runtimes, for independent implementations and adoption.
- Red teamers and security auditors.

## How to contribute

- Open an issue or pull request on this repository.
- Or email info@opena2a.org with "co-author" in the subject line.
- For cryptographic findings, signature weaknesses, or coordinated disclosure, email info@opena2a.org.

Small fixes (typos, broken links, clarifications) can go straight to a pull request. For anything that changes the credential format, signature suite, or verification algorithm, open an issue first so the change can be discussed before implementation work begins.

## Ground rules

- Be specific and evidence-based. Point to the section, the field, or the failing case.
- No purely theoretical claims without a path to validation. If you propose a change, describe how it could be tested against the conformance suite or implemented.

## License of contributions

Contributions are accepted under the license of this repository, the Apache License 2.0, in [LICENSE](LICENSE). By contributing, you agree that your contributions are licensed under the Apache License 2.0.

## Sign your work

Every commit of a contribution must carry a `Signed-off-by: Name <email>` line, which `git commit -s` adds. By that line you certify the [Developer Certificate of Origin 1.1](https://developercertificate.org), whose four clauses read:

> Developer's Certificate of Origin 1.1
>
> By making a contribution to this project, I certify that:
>
> (a) The contribution was created in whole or in part by me and I
>     have the right to submit it under the open source license
>     indicated in the file; or
>
> (b) The contribution is based upon previous work that, to the best
>     of my knowledge, is covered under an appropriate open source
>     license and I have the right under that license to submit that
>     work with modifications, whether created in whole or in part
>     by me, under the same open source license (unless I am
>     permitted to submit under a different license), as indicated
>     in the file; or
>
> (c) The contribution was provided directly to me by some other
>     person who certified (a), (b) or (c) and I have not modified
>     it.
>
> (d) I understand and agree that this project and the contribution
>     are public and that a record of the contribution (including all
>     personal information I submit with it, including my sign-off) is
>     maintained indefinitely and may be redistributed consistent with
>     this project or the open source license(s) involved.

No contributor license agreement is asked for. The names and logos of the project are not licensed by the code license: section 6 of the Apache License 2.0 grants no permission to use them.
