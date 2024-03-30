# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.virtualization.microvm-host;
in
  with lib; {
    options.ghaf.virtualization.microvm-host = {
      enable = mkEnableOption "MicroVM Host";
      networkSupport = mkEnableOption "Network support services to run host applications.";
    };

    config = mkIf cfg.enable {
      microvm.host.enable = true;
      ghaf.systemd = {
        withName = "host-systemd";
        enable = true;
        boot.enable = true;
        withPolkit = true;
        withTpm2Tss = pkgs.stdenv.hostPlatform.isx86;
        withRepart = true;
        withFido2 = true;
        withCryptsetup = true;
        withTimesyncd = cfg.networkSupport;
        withNss = cfg.networkSupport;
        withResolved = cfg.networkSupport;
        withSerial = config.ghaf.profiles.debug.enable;
        withDebug = config.ghaf.profiles.debug.enable;
      };
    };
  }
