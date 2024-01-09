<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Security Policy

This document includes information about the vulnerability reporting, patch,
release, and disclosure processes, as well as general security posture.

<!-- markdown-toc --bullets="-" -i SECURITY.md -->

<!-- toc -->

- [Supported Versions](#supported-versions)
- [Reporting a Vulnerability](#reporting-a-vulnerability)
  - [When Should I Report a Vulnerability?](#when-should-i-report-a-vulnerability)
  - [When Should I NOT Report a Vulnerability?](#when-should-i-not-report-a-vulnerability)
  - [Vulnerability Response](#vulnerability-response)
- [Security Release & Disclosure Process](#security-release--disclosure-process)
  - [Private Disclosure](#private-disclosure)
  - [Public Disclosure](#public-disclosure)
  - [Security Releases](#security-releases)
  - [Severity](#severity)
- [Security Team](#security-team)
- [Security Policy Updates](#security-policy-updates)

<!-- tocstop -->

## Supported Versions

The following versions are currently supported and receive security updates.
Release candidates will not receive security updates.

| Version  | Supported          |
| -------- | ------------------ |
| >= 23.12 | :white_check_mark: |
| <=23.09  | :x:                |

## Reporting a Vulnerability

We're extremely grateful for security researchers and users that report
vulnerabilities to us. All reports are thoroughly investigated by the project
[security team](#security-team).

Vulnerabilities are reported privately via GitHub's
[Security Advisories](https://docs.github.com/en/code-security/security-advisories)
feature. Please use the following link to submit your vulnerability:
[Report a vulnerability](https://github.com/tiiuae/ghaf/security/advisories/new)

Please see
[Privately reporting a security vulnerability](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability#privately-reporting-a-security-vulnerability)
for more information on how to submit a vulnerability using GitHub's interface.

### When Should I Report a Vulnerability?

- You think you discovered a potential security vulnerability in Ghaf
- You are unsure how a vulnerability affects Ghaf
- You think you discovered a vulnerability in another project that Ghaf depends on
  - For projects with their own vulnerability reporting and disclosure process, please report it directly there

### When Should I NOT Report a Vulnerability?

- You need help tuning GitHub Actions for security
- You need help applying security related updates
- When the issue is currently acknowledged in [Security Advisory](https://github.com/tiiuae/ghafscan/blob/main/reports/main/README.md)
- Your issue is not security related

### Vulnerability Response

Each report is acknowledged and analyzed by the [Security Team](#security-team)
within 14 days. This will set off the
[Security Release Process](#security-release--disclosure-process).

Any vulnerability information shared with the Security Team stays within
Ghaf project and will not be disseminated to other projects
unless it is necessary to get the issue fixed.

As the security issue moves from triage, to identified fix, to release planning
we will keep the reporter updated.

## Security Release & Disclosure Process

Security vulnerabilities should be handled quickly and sometimes privately. The
primary goal of this process is to reduce the total time users are vulnerable
to publicly known exploits.

### Private Disclosure

We ask that all suspected vulnerabilities be privately and responsibly
disclosed via the [private disclosure process](#reporting-a-vulnerability)
outlined above.

Fixes may be developed and tested by the [Security Team](#security-team) in a
[temporary private fork](https://docs.github.com/en/code-security/security-advisories/repository-security-advisories/collaborating-in-a-temporary-private-fork-to-resolve-a-repository-security-vulnerability)
that are private from the general public if deemed necessary.

### Public Disclosure

Vulnerabilities are disclosed publicly as [Security
Advisories](https://github.com/tiiuae/ghafscan/blob/main/reports/main/README.md).

A public disclosure date is negotiated by the [Security Team](#security-team)
and the bug submitter. We prefer to fully disclose the bug as soon as possible
once a user mitigation is available. It is reasonable to delay disclosure when
the bug or the fix is not yet fully understood, the solution is not
well-tested, or for vendor coordination. The timeframe for disclosure is from
immediate (especially if it's already publicly known) to several weeks. For a
vulnerability with a straightforward mitigation, we expect report date to
disclosure date to be on the order of 14 days.

If you know of a publicly disclosed security vulnerability please IMMEDIATELY
[report the vulnerability](#reporting-a-vulnerability) to inform the
[Security Team](#security-team) about the vulnerability so they may start the
patch, release, and communication process.

If possible the Security Team will ask the person making the public report if
the issue can be handled via a private disclosure process. If the reporter
denies the request, the Security Team will move swiftly with the fix and
release process. In extreme cases you can ask GitHub to delete the issue but
this generally isn't necessary and is unlikely to make a public disclosure less
damaging.

### Security Releases

Once a fix is available it will be released and announced via the project on
GitHub, releases will announced and clearly marked as a security release and
include information on which vulnerabilities were fixed. As much as possible
this announcement should be actionable, and include any mitigating steps users
can take prior to upgrading to a fixed version.

Fixes will be applied in patch releases to all [supported
versions](#supported-versions) and all fixed vulnerabilities will be noted in
the [Release Notes](https://tiiuae.github.io/ghaf/release_notes/release_notes.html).

### Severity

The [Security Team](#security-team) evaluates vulnerability severity on a
case-by-case basis, guided by [CVSS 3.1](https://www.first.org/cvss/v3.1/specification-document).

## Security Team

The Security Team is responsible for the overall security of the
project and for reviewing reported vulnerabilities. Each member is familiar
with designing secure software, security issues related to CI/CD, GitHub
Actions and build provenance.

Security Team:

- Brian McGillion (@brianmcgillion)
- Manuel Bluhm (@mbssrc)
- Henri Rosten (@henrirosten)
- Mika Tammi (@mikatammi)

Security Team membership is currently considered on a case-by-case basis.

## Security Policy Updates

Changes to this Security Policy are reviewed and approved by the
[Security Team](#security-team).
