# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.virtualization.host.bpmp;
in
{
  _file = ./default.nix;

  options.ghaf.hardware.nvidia.virtualization.host.bpmp = {
    enable = lib.mkEnableOption "NVIDIA Orin BPMP host virtualization support";
    allow = {
      clocks = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [ ];
        apply = lib.unique;
        description = "Raw BPMP clock IDs the host proxy forwards.";
      };
      resets = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [ ];
        apply = lib.unique;
        description = "Raw BPMP reset IDs the host proxy forwards.";
      };
      powerDomains = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [ ];
        apply = lib.unique;
        description = "Raw BPMP power-domain IDs the host proxy forwards.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.nvidia-jetpack.virtualization.bpmpHost = {
      allowAllDomains = config.ghaf.hardware.nvidia.virtualization.bpmpAllowAllDomains;
      consumers.legacy = cfg.allow;
    };

    # Keep the device name expected by the existing QEMU passthrough modules.
    # Named per-VM proxies replace this compatibility link in the next layer.
    services.udev.extraRules = ''
      KERNEL=="bpmp-host-legacy", SYMLINK+="bpmp-host"
    '';
  };
}
