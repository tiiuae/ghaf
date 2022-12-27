# Patching Automation

Patching automation increases complex software development efficiency concurrently ensuring high level of vulnerability remediation in a reasonable time frame.

Each software artifact is undergoing a vulnerability scanning immediately after the build. When new vulnerabilities are discovered, the system will scan each dependency provenance for update availability. In case such exists, it will be downloaded and the new package will be built. The fresh package will undergo the same scan and a full set of functional testing, ensuring no functionality shatter was introduced simultaneously listing all new vulnerabilities introduced by the updates. A package passing the testing will be presented to the concerned developers for review and approval. All approved artifacts become release candidates as per adapted process.

![AutomaticPatching](../img/autopatching.drawio.png)

## Implementation

### Package URL

The dependency tracking solution is based on Package URL (PURL), natively supported by ClyconeDX. PURL is a URL, composed of seven components:

`scheme:type/namespace/name@version?qualifiers#subpath`

  + **scheme**: URL scheme, with the constant value "pkg", facilitating the future official registration of the "pkg" scheme for package URLs
  + **type**: the package type, such as npm, maven, etc
  + **namespace**: name prefix. For example GitHub user, organization, etc
  + **name**: the name of the package
  + **version**: the version of the package
  + **qualifiers**: extra qualifying data, e.g. OS, distro, architecture, etc
  + **subpath**: extra subpath relative to package root

In addition to PURL, each component should contain at least one hash value, computed from cryptographic hash functions. The hash values help verifying original package integrity and source prior to update download. Thus minimizing security risks during the process.
