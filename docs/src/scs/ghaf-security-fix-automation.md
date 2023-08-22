<!--
    Copyright 2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Security Fix Automation

The Nix community is able to identify and fix security issues relatively quickly. At the same time, the community process to ensure critical security fixes are included in nixpkgs is unclear or unspecified.

Indeed, Ghaf should not solely rely on the community to provide security fixes but take action to understand the vulnerabilities that impact Ghaf and take an active role in fixing such issues.

## Semi-Automated Upstream-First Process

The following image captures the high-level process we propose to identify and remediate the security vulnerabilities that impact Ghaf:

![Security Fix Automation](../img/ghaf-security-fix-automation.drawio.svg "Ghaf Security Fix Automation")

The process consists of two parts - **automated** and **manual**:

- **Automated vulnerability analysis** is a scripted job triggered on a daily basis in Ghaf CI/CD. It consists of the following actions:

  **(1)** Locally (temporarily) update the Ghaf flake lock file. Temporary lock file update is needed so the Ghaf dependencies are up-to-date with the nixpkgs input Ghaf is pinned to. Otherwise, the automated analysis results would also include vulnerabilities that have been fixed in nixpkgs upstream since the last Ghaf flake lock update.

  **(2)** Run automated vulnerability analysis tooling for each relevant Ghaf build target. For Ghaf, being Nix-based, we propose to use [nix_secupdates](https://github.com/tiiuae/sbomnix/tree/main/scripts/nixupdate#nix_secupdates) for automated vulnerability analysis. As a result of this step, the tooling generates an auto-triaged vulnerability report, which will be the main input for the manual analysis.

- **Manual vulnerability analysis** is a manual process, which is also executed on daily basis.

  **(3)** Using the auto-triaged vulnerability report from the previous step, manually analyze the automation results comparing the new results to earlier day's results from the relevant build.

  **(4)** If there are any fixed issues compared to the last analyzed report, initiate the Ghaf flake lock file update for relevant inputs to include the vulnerability fixes from the nixpkgs upstream to relevant Ghaf branches.

  **(5)** If there are any new vulnerabilities compared to the last analyzed report, manually analyze each vulnerability in detail. If the issue requires a fix, create a pull request to push the changes to relevant nixpkgs branches.

The process described above is an upstream-first, with the main benefit of eliminating the need to maintain our own vulnerability fix patches on top of nixpgks in Ghaf. This process will also benefit the nixpkgs community, contributing to the overall security improvement for the packages Ghaf depends on.
