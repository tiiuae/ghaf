# Supply Chain Security

Supply Chain Security (SCS) is a process of securing the machinery of the development, building and release environment. That means every component that a software artifact might be touching on its way from the developer towards the consumer will be secured. The software artifact should be encrypted on each possible transition phase and its integrity should be verified at each destination. Each build should be acompanied with Software Bill Of Materials (SBOM), identifying all the components that software package consists of.

The Software Bill Of Materials (SBOM) containing reference to each dependency, its source and version togerher with provenance, containing build information are collected at the build time, signed and used for vulnerability analysis during the next steps.

The software artifact, SBOM and provenance are signed by the build machinery at the build time and the signature is verifiable at every destination of the package. The certificates that are used for signing and verification are provided by the Public Key Infrastructure (PKI) system and are signed by the same root Certificate Authority (CA), thus making it possible to easily confirm the signature author (build machinery) and guarantee that the package has not been tampered with since the build time.

![Scope](./img/scope.png)
