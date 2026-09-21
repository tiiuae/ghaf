# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  globalConfig,
  lib,
  ...
}:
let
  globallyEnabled = globalConfig.logging.logseald.enable or false;
in
{
  _file = ./global-logseald-policy.nix;

  ghaf.logging.logseald = {
    producer.enable = lib.mkDefault (globallyEnabled && config.ghaf.logging.enable);
    endpoint.port = lib.mkDefault (globalConfig.logging.logseald.port or 59631);
  };
}
