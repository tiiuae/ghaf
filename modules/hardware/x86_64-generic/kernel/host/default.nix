# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Importing kernel builder function from packages and checking hardening options
  buildKernel = import ../../../../../packages/kernel {inherit config pkgs lib;};
  config_baseline = ../configs/ghaf_host_hardened_baseline-x86;
  host_hardened_kernel = buildKernel {
    inherit config_baseline;
    host_build = true;
  };

  enable_kernel_hardening = config.ghaf.host.kernel.hardening.enable;
in
  with lib; {
    options.ghaf.host.kernel.hardening.enable = mkOption {
      description = "Enable Ghaf Host hardening feature";
      type = types.bool;
      default = false;
    };

    options.ghaf.host.kernel.hardening.virtualization.enable = mkOption {
      description = "Enable support for virtualization in the Ghaf Host";
      type = types.bool;
      default = false;
    };

    options.ghaf.host.kernel.hardening.networking.enable = mkOption {
      description = "Enable support for networking in the Ghaf Host";
      type = types.bool;
      default = false;
    };

    options.ghaf.host.kernel.hardening.usb.enable = mkOption {
      description = "Enable support for USB in the Ghaf Host";
      type = types.bool;
      default = false;
    };

    options.ghaf.host.kernel.hardening.inputdevices.enable = mkOption {
      description = "Enable support for input devices in the Ghaf Host";
      type = types.bool;
      default = false;
    };

    options.ghaf.host.kernel.hardening.debug.enable = mkOption {
      description = "Enable support for debug features in the Ghaf Host";
      type = types.bool;
      default = false;
    };

    config = mkIf enable_kernel_hardening {
      boot.kernelPackages = pkgs.linuxPackagesFor host_hardened_kernel;
      # https://github.com/NixOS/nixpkgs/issues/109280#issuecomment-973636212
      nixpkgs.overlays = [
        (_final: prev: {
          makeModulesClosure = x:
            prev.makeModulesClosure (x // {allowMissing = true;});
        })
      ];
    };
  }
