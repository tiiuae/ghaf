# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Developed against cryptsetup 2.8.7; recheck offline conversion on version bumps.
{ cryptsetup }:
cryptsetup.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./offline-file-convert.patch ];
  configureFlags = (old.configureFlags or [ ]) ++ [
    "--with-luks2-lock-path=/tmp/cryptsetup"
  ];
  # The upstream suite requires privileged kernel mappings. The consumer's
  # ghaf-wrap-luks-image.tests.roundtrip covers regular-file conversion only.
  doCheck = false;
})
