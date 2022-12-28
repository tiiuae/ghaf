# Patch Management Automation

Patch management automation increases complex software development efficiency concurrently ensuring high level of vulnerability remediation in a reasonable time frame.

The process is:

  - Build the package
  - Scan for vulnerabilities
  - If no new vulnerabilities are discovered the package undergoes testing followed by the developer review
  - Check for update availability and upgrade
  - Rebuild the package
  - Rescan and send it to the automatic testing, followed by the developer review
  
![AutomaticPatching](../img/autopatching.drawio.png)

## Implementation

### Dependency Tracking

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

### Package Update

The update mechanism implementation is system dependent and will differ from build system to another. For example in Nix it is enough that respective nix files are automatically updated and the package is rebuilt. More information on package update steps is available in ![NixOSWiki](https://nixos.wiki/wiki/Update_a_package).
