# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.virtualization.microvm-host;
in {
  options.ghaf.virtualization.microvm-host = {
    enable = lib.mkEnableOption "MicroVM Host";
    networkSupport = lib.mkEnableOption "Network support services to run host applications.";
  };

  config = lib.mkIf cfg.enable {
    microvm.host.enable = true;
    ghaf.systemd = {
      withName = "host-systemd";
      enable = true;
      boot.enable = true;
      withAudit = config.ghaf.profiles.debug.enable;
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
      withHardenedConfigs = true;
    };

    # TODO: remove hardcoded paths
    systemd.services."microvm@audio-vm".serviceConfig = lib.optionalAttrs config.ghaf.virtualization.microvm.audiovm.enable {
      # The + here is a systemd feature to make the script run as root.
      ExecStopPost = [
        "+${pkgs.writeShellScript "reload-audio" ''
          # The script makes audio device internal state to reset
          # This fixes issue of audio device getting into some unexpected
          # state when the VM is being shutdown during audio mic recording
          echo "1" > /sys/bus/pci/devices/0000:00:1f.3/remove
          sleep 0.1
          echo "1" > /sys/bus/pci/devices/0000:00:1f.0/rescan
        ''}"
      ];
    };
  };
}
