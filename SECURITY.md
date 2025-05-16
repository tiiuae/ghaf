<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Security Policy

This document includes information about the vulnerability reporting, patch,
release, disclosure processes, and the general security posture.

<!-- markdown-toc --bullets="-" -i SECURITY.md -->

<!-- toc -->

- [Security Policy](#security-policy)
  - [Supported Versions](#supported-versions)
  - [Security Team](#security-team)
  - [Reporting Vulnerability](#reporting-vulnerability)
    - [When Should I Report Vulnerability?](#when-should-i-report-vulnerability)
    - [When Should I NOT Report Vulnerability?](#when-should-i-not-report-vulnerability)
    - [Vulnerability Response](#vulnerability-response)
  - [Security Release \& Disclosure Process](#security-release--disclosure-process)
    - [Private Disclosure](#private-disclosure)
    - [Public Disclosure](#public-disclosure)
    - [Security Releases](#security-releases)
    - [Severity](#severity)
  - [Security Policy Updates](#security-policy-updates)

<!-- tocstop -->

## Supported Versions

The following versions are currently supported and receive security updates.
Release candidates will not receive security updates.

| Version  | Supported          |
| -------- | ------------------ |
| >= 23.12 | :white_check_mark: |
| <= 23.09  | :x:               |


## Security Team

The Security Team is responsible for the overall security of the project and for reviewing reported vulnerabilities. Each member is familiar with designing secure software, security issues related to CI/CD, GitHub Actions, and build provenance.

Security Team:

* Brian McGillion (@brianmcgillion)
* Manuel Bluhm (@mbssrc)
* Henri Rosten (@henrirosten)
* Ganga Ram (@gngram)

Security Team membership is currently considered on a case-by-case basis.


## Reporting Vulnerability

We are grateful to security researchers and users who report vulnerabilities. The project [Security Team](#security-team) thoroughly investigates all reports.

You can report security vulnerabilities directly (privately or publicly) to the security team by using the [Report a vulnerability](https://github.com/tiiuae/ghaf/security/advisories/new) form, as the ghaf repository is configured with the GitHub's [Security Advisories](https://docs.github.com/en/code-security/security-advisories) feature. For information on how to submit a vulnerability using GitHub's interface, see [Privately reporting a security vulnerability](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability#privately-reporting-a-security-vulnerability).


### When Should I Report Vulnerability?

* You think you discovered a potential security vulnerability in Ghaf.
* You are unsure how a vulnerability affects Ghaf.
* You think you discovered a vulnerability in another project that Ghaf depends on.

> For projects with their own vulnerability reporting and disclosure process, report it directly there.


### When Should I NOT Report Vulnerability?

* You need help tuning GitHub Actions for security.
* You need help applying security-related updates.
* When the issue is currently acknowledged in [Ghaf Vulnerability Reports](https://github.com/tiiuae/ghafscan/blob/main/reports/main/README.md).
* Your issue is not security-related.


### Vulnerability Response

Each report is acknowledged and analyzed by the [Security Team](#security-team) within 14 days. This sets off the [Security Release & Disclosure Process](#security-release--disclosure-process).

Any vulnerability information shared with the Security Team stays within the Ghaf project and will not be disseminated to other projects unless it is necessary to get the issue fixed.

We keep a reporter updated as the security issue moves from triage to identified fix, and then to release planning.


## Security Release & Disclosure Process

Security vulnerabilities are handled quickly and sometimes privately. The primary goal of this process is to reduce the total time users are vulnerable to publicly known exploits.


### Private Disclosure

We ask that all suspected vulnerabilities be privately and responsibly disclosed through the [private disclosure process](#reporting-a-vulnerability) outlined above. Fixes may be developed and tested by the [Security Team](#security-team) in a [temporary private fork](https://docs.github.com/en/code-security/security-advisories/repository-security-advisories/collaborating-in-a-temporary-private-fork-to-resolve-a-repository-security-vulnerability) that is private from the general public if deemed necessary.


### Public Disclosure

Vulnerabilities are disclosed publicly as [Security Advisories](https://github.com/tiiuae/ghafscan/blob/main/reports/main/README.md).

A public disclosure date is negotiated by the [Security Team](#security-team) and a vulnerability reporter. We prefer to fully disclose the bug as soon as possible once a user mitigation is available. It is reasonable to delay disclosure when a bug or fix is not yet fully understood, the solution is not well-tested, or for vendor coordination. The time frame for disclosure is from immediate (especially if it is already publicly known) to several weeks. For a vulnerability with straightforward mitigation, we expect a report date to disclosure date to be on the order of 14 days.

If you know of a publicly disclosed security vulnerability, please *IMMEDIATELY* [report the vulnerability](#reporting-a-vulnerability) to inform the [Security Team](#security-team), so they may start the patch, release, and communication process.

If possible the Security Team will ask the person making the public report if the issue can be handled via a private disclosure process. If the reporter denies the request, the Security Team will move swiftly with the fix and release process. In extreme cases, you can use GitHub to delete the issue but this generally isn not necessary and is unlikely to make a public disclosure less damaging.


### Security Releases

Once a fix is available, it will be released and announced in the project on GitHub, releases will announced and marked as a security release and include information on which vulnerabilities were fixed. As much as possible this announcement should be actionable and include any mitigating steps users can take before upgrading to a fixed version.

Fixes will be applied in patch releases to all [supported versions](#supported-versions) and all fixed vulnerabilities will be noted in the [Release Notes](https://ghaf.tii.ae/ghaf/releases/release_notes/).


### Severity

The [Security Team](#security-team) evaluates vulnerability severity on a case-by-case basis, guided by the [CVSS 3.1](https://www.first.org/cvss/v3.1/specification-document) specification document.


## Security Policy Updates

Changes to this Security Policy are reviewed and approved by the [Security Team](#security-team).
