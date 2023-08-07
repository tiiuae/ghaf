<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Software Bill of Materials (SBOM)

Software bill of materials (SBOM) is a formal, machine-readable document that provides a list of software components that make up the target software and all its dependencies.


## SBOM Formats and Specifications

There are three main delivery formats and specifications for SBOM: CycloneDX, SPDX, and SWID.

[CycloneDX](https://cyclonedx.org/specification/overview/) is an open-source standard with origins in the [OWASP](https://en.wikipedia.org/wiki/OWASP) community. The specification's original focus is on security. There's a large growing community and open source tooling that support CycloneDX format.

[SPDX](https://spdx.dev/specifications/) is also a product of an open-source community, with the original focus on licensing. SPDX is run and maintained by [Linux Foundation](https://en.wikipedia.org/wiki/Linux_Foundation). Similarly to CycloneDX, many open-source tools support the SPDX format. 

[SWID](https://nvd.nist.gov/products/swid) is a [standard](https://www.iso.org/standard/65666.html) that originates from [NIST](https://www.nist.gov/). SWID tags aim to help organizations create accurate software inventories. While SWID can serve as an SBOM too, it is not as widely used SBOM format in open source as the two other specifications.


## SBOM Usage in Ghaf

Ghaf framework will use SBOMs for:

- Vulnerability identification: automatic correlation of SBOM against known vulnerabilities.
- Vulnerability remediation: automatic process to suggest fixes for identified vulnerabilities.
- Dependency analysis: categorization of open-source and closed source software dependencies.
- Dependency analysis: creation of a directed acyclic graph
- License compliance: know and comply with the license obligations.
- Market signal: publish SBOM together with other release artifacts.


## SBOM Tooling in Ghaf

Ghaf is based on Nix, therefore, the selected SBOM tooling needs to support creating SBOMs for nix artifacts. As part of the Ghaf project, we have created the sbomnix tool to support SBOM generation for Ghaf and, more generally, for any Nix-based targets. For more details on the SBOM tooling in Ghaf, see [sbomnix](https://github.com/tiiuae/sbomnix#sbomnix) and [nixgraph](https://github.com/tiiuae/sbomnix/blob/main/doc/nixgraph.md#nixgraph). sbomnix supports [CycloneDX](https://cyclonedx.org/specification/overview/) as well as [SPDX](https://spdx.dev/specifications/) SBOM specification.


## References

- <https://ntia.gov/page/software-bill-materials>
- <https://slsa.dev/blog/2022/05/slsa-sbom>
- <https://fossa.com/blog/software-bill-of-materials-formats-use-cases-tools>
- <https://www.legitsecurity.com/blog/what-is-an-sbom-sbom-explained-in-5-minutes>