# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  microvm,
}: let
  base = import ./vm.nix {inherit self microvm;};
in
  base
  // {
    modules = base.modules ++ [../modules/development/intel-nuc-getty.nix];
  }
