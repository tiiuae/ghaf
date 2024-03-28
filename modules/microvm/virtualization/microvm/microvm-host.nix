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
      x86Support = mkEnableOption "Enable x86 specific services.";
      networkSupport = mkEnableOption "Network support services to run host applications.";
    };

    config = mkIf cfg.enable {
      microvm.host.enable = true;
      ghaf.systemd = {
        withName = "host-systemd";
        enable = true;
        boot.enable = true;
        withPolkit = true;
        withTpm2Tss = cfg.x86Support;
        withRepart = cfg.x86Support;
        withCryptsetup = cfg.x86Support;
        withTimesyncd = cfg.networkSupport;
        withNss = cfg.networkSupport;
        withResolved = cfg.networkSupport;
        withSerial = config.ghaf.profiles.debug.enable;
        withDebug = config.ghaf.profiles.debug.enable;
      };
    };
  }
