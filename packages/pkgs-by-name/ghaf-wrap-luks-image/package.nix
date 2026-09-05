# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, stdenv }:
inputs.ghafpkgs.packages.${stdenv.hostPlatform.system}.ghaf-wrap-luks-image
