# SCS

Supply Chain Security is a process of securitng the machinery of the development, build and release environment, in other words, securing every component that a software artifact might be touching on its way from the developer towards the consumer. The software artifact should be encrypted on each possilbe transition phase and the integrity of it should be verified at each destination.

The SBOM (Software Bill Of Materials) containing reference to each dependency, its source and version togerher with provenance, containing build information are collected at the build time, signed and used for vulnerability analysis during the next steps. The SBOM is also published together with the final image, thus making further analysis of the software possible by the end customer.

The software artifact, SBOM and provenance are signed by the build machinery at the build time and the signature is verifiable at every destination of the package. The certificates that are used for signing and verification are provided by the PKI system and are signed by the same root CA, thus making it possible to easily confirm the signature author (build machinery) and guarantee that the package has not been tampered with since the build time.
