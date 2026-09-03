<!--
    SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Secure A/B CI build configuration

This input is intentionally limited to pure evaluation and build coverage.
It selects generation 1, the repository development UEFI certificates, and
the RFC 8032 test-vector Ed25519 public key in `update.pub`. The corresponding
private keys are public knowledge, so adapters must not deploy this trust set.

Development and release builds override `secure-ab-build-config` with a source
containing `config.json`, `PK.crt`, `KEK.crt`, `db.crt`, and `update.pub`.
Private keys and recovery material must never be added to that source.
