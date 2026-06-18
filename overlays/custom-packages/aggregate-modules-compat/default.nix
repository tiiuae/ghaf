# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# nixpkgs vmTools (>= 26.11.20260615) requires kernel.target to determine the
# boot image filename. disko passes kernel = pkgs.aggregateModules([...]) which
# is a plain buildEnv with no .target attribute, breaking the vmTools check.
#
# Propagate .target from the first module in the list that carries it so the
# vmTools kernelImage default (kernel.target or throw) succeeds - restoring the
# old vmTools behaviour where img defaulted to stdenv.hostPlatform.linux-kernel.target.
{ prev }:
modules:
let
  result = prev.aggregateModules modules;
  kernelModule = prev.lib.findFirst (m: m ? target) null modules;
in
if kernelModule != null then result // { inherit (kernelModule) target; } else result
