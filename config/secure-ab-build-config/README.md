<!--
SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Secure A/B public configuration template

This placeholder contains no keys. Secure A/B targets fail evaluation until
`secure-ab-build-config` is overridden with an external public configuration.
Export one with `ghaf-secure-ab-config`, then use its output as a pure flake
input. Private keys must remain outside the input and the Nix store.
