<!--
    SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->
<div align="center">
  <img src="./docs/src/assets/ghaf-logo.svg" alt="Ghaf Logo" width="25%" height="25%" />
  <h1>Ghaf Framework</h1>
  <p>TII SSRC Secure Technologies</p>
</div>

<div align="center">

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-darkgreen.svg)](./LICENSES/LICENSE.Apache-2.0) [![License: CC-BY-SA 4.0](https://img.shields.io/badge/License-CC--BY--SA--4.0-orange.svg)](./LICENSES/LICENSE.CC-BY-SA-4.0) [![Style Guide](https://img.shields.io/badge/docs-Style%20Guide-yellow)](https://github.com/tiiuae/ghaf/blob/main/docs/style_guide.md) [![OpenSSF Best Practices](https://www.bestpractices.dev/projects/8290/badge)](https://www.bestpractices.dev/projects/8290) [![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](./CODE_OF_CONDUCT.md)

</div>

This repository contains the source files (code and documentation) of Ghaf Framework — an open-source project for enhancing security through compartmentalization on edge devices.

For information on build instructions and supported hardware, see the [Reference Implementations](https://ghaf.tii.ae/ghaf/dev/ref/) section of Ghaf documentation.



### Documentation

The Ghaf Framework documentation site is located under <https://ghaf.tii.ae>. It is under cooperative development.

To build Ghaf documentation, use:

    nix build .#doc

See the documentation overview under [README-docs.md](./docs/README-docs.md).


## Other Project Repositories

Other repositories that are a part of the Ghaf project:

* [sbomnix](https://github.com/tiiuae/sbomnix): a utility that generates SBOMs given Nix derivations or out paths
* [ghaf-infra](https://github.com/tiiuae/ghaf-infra), [ci-test-automation](https://github.com/tiiuae/ci-test-automation), [ghafscan](https://github.com/tiiuae/ghafscan): CI/CD related files
* [ghafpkgs](https://github.com/tiiuae/ghafpkgs): a repository for Ghaf-specific Nix packages
* [ghaf-installation-wizard](https://github.com/tiiuae/ghaf-installation-wizard): helps you install Ghaf for the first time


## Build System

Ghaf images are built and tested by our continuous integration system. For more information on a general process, see [Continuous Integration and Distribution](https://ghaf.tii.ae/ghaf/scs/ci-cd-system/).


## Contributing

We welcome your contributions to code and documentation.

If you would like to contribute, please read [CONTRIBUTING.md](CONTRIBUTING.md) and consider opening a pull request. One or more maintainers will use GitHub's review feature to review your pull request.

In case of any bugs or errors in the content, feel free to create an [issue](https://github.com/tiiuae/ghaf/issues). You can also [create an issue from code](https://docs.github.com/en/issues/tracking-your-work-with-issues/creating-an-issue#creating-an-issue-from-code).


## Licensing

The Ghaf team uses multiple licenses to distribute software and documentation:

| License Full Name | SPDX Short Identifier | Description |
| -------- | ----------- | ----------- |
| Apache License 2.0 | [Apache-2.0](https://spdx.org/licenses/Apache-2.0.html) | Ghaf source code. |
| Creative Commons Attribution Share Alike 4.0 International | [CC-BY-SA-4.0](https://spdx.org/licenses/CC-BY-SA-4.0.html) | Ghaf documentation. |

See [LICENSE.Apache-2.0](./LICENSES/Apache-2.0.txt) and [LICENSE.CC-BY-SA-4.0](./LICENSES/CC-BY-SA-4.0.txt) for the full license text.
