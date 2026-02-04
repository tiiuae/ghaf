# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# Copyright TLATER
#
# SPDX-License-Identifier: Apache-2.0
# from https://github.com/TLATER/dotfiles
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
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
    enable = mkOption {
      description = ''
        prime offload. This will allow on-demand offloading
        of rendering tasks to the NVIDIA GPU, all other
        rendering will happen on the GPU integrated in the CPU.

        The GPU *should* be turned off whenever it is not in use, so
        this shouldn't cause increased battery drain, but there are
        some reports floating around that this isn't always the case -
        likely especially for older devices. Feel free to turn it off
        if you find this doesn't work properly for you.
      '';
      type = types.bool;
      default = false;
    };

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
