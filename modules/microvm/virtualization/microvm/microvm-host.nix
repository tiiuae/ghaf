# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.virtualization.microvm-host;
in
  with lib; {
    options.ghaf.virtualization.microvm-host = {
      enable = mkEnableOption "MicroVM Host";
      hostNetworkSupport = mkEnableOption "Network support services to run host applications.";
    };

    config = mkIf cfg.enable {
      microvm.host.enable = true;
      ghaf.systemd = {
        enable = true;
        withName = "host-systemd";
        withPolkit = true;
        withTimesyncd = cfg.hostNetworkSupport;
        withNss = cfg.hostNetworkSupport;
        withResolved = cfg.hostNetworkSupport;
        withSerial = config.ghaf.profiles.debug.enable;
        withDebug = config.ghaf.profiles.debug.enable;
      };
    };
  }
