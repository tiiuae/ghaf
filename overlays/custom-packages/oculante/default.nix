# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay customizes oculante
#
{ prev }:

prev.oculante.overrideAttrs (oldAttrs: {
  # nixpkgs applies the libaom patch against vendored Cargo sources.
  # Recent cargo vendor output places crates under source-registry-0.
  patchFlags = [
    "-p1"
    "--directory=../${oldAttrs.pname}-${oldAttrs.version}-vendor/source-registry-0"
  ];
})
