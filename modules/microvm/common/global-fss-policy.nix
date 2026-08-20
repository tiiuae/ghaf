# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  globalConfig,
  lib,
  ...
}:
let
  globalFssEnabled = globalConfig.logging.fss.enable or true;
in
{
  _file = ./global-fss-policy.nix;

  # Global off must override local enables; global on still permits stateless VMs.
  ghaf.logging.fss.enable =
    if globalFssEnabled then lib.mkDefault config.ghaf.logging.enable else lib.mkForce false;
}
