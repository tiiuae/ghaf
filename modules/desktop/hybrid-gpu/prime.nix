# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# Copyright TLATER
#
# SPDX-License-Identifier: Apache-2.0
# from https://github.com/TLATER/dotfiles
{ config, lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
  inherit (config.ghaf.graphics.hybrid-setup.prime) nvidiaBusId intelBusId;
  cfg = config.ghaf.graphics.hybrid-setup.prime;
  environmentVariables = {
    # To run an application offloaded to the NVIDIA GPU
    __NV_PRIME_RENDER_OFFLOAD = "1";
  };
in
{
  _file = ./prime.nix;

  options.ghaf.graphics.hybrid-setup.prime = {
    enable = mkEnableOption "NVIDIA PRIME offload rendering";

    nvidiaBusId = mkOption {
      description = ''
        Bus ID of the NVIDIA GPU. You can find it using lspci;
        for example if lspci shows the NVIDIA GPU at “0001:02:03.4”,
        set this option to “PCI:2@1:3:4”.
      '';
      type = types.str;
      default = "";
    };

    intelBusId = mkOption {
      description = ''
        Bus ID of the Intel GPU. You can find it using lspci;
        for example if lspci shows the Intel GPU at “0001:02:03.4”,
        set this option to “PCI:2@1:3:4”.
      '';
      type = types.str;
      default = "";
    };
  };

  config = lib.mkIf cfg.enable {

    assertions = [
      {
        assertion = nvidiaBusId != "";
        message = "Please provide Nvidia Bus ID or disable the prime module.";
      }
      {
        assertion = intelBusId != "";
        message = "Please provide a Intel Bus ID or disable the prime module.";
      }
    ];

    hardware.nvidia = {
      prime = {
        offload.enable = true;
        offload.enableOffloadCmd = true;
        inherit nvidiaBusId;
        inherit intelBusId;
      };

      powerManagement.finegrained = true;
    };

    environment.sessionVariables = environmentVariables;
  };
}
