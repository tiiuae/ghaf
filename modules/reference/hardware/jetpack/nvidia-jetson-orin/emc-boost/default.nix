# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Let the EMC (DRAM) clock reach its trained maximum instead of being
# capped at the boot rate.
#
# BPMP firmware boots with an internal bandwidth-manager cap at the DRAM
# boot rate (2133 MHz on AGX Orin), so without intervention the memory bus
# never reaches the trained maximum (3199 MHz on AGX Orin — a ~50% memory
# bandwidth loss under load, for every workload on the device). Stock
# JetPack lifts the cap from the nvphs service; Ghaf does not run it, and
# the nvpmodel sysfs cap interface cannot raise the cap (its own request
# is rounded through a call the cap clamps). See
# emc-boost/module/emc_cap_lift.c for the full analysis.
#
# The emc_cap_lift.ko module lifts the cap once at boot (a kernel module,
# because the CAP_SET MRQ is not reachable from userspace). No rate
# pinning is done: with the cap lifted, the demand-driven EMC DVFS
# governor ranges freely — validated on AGX Orin hardware to reach
# 3199 MHz under memory load and drop back to 204 MHz at idle.
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin.emcBoost;
in
{
  _file = ./default.nix;

  options.ghaf.hardware.nvidia.orin.emcBoost = {
    enable = lib.mkEnableOption "running the EMC (DRAM) clock at its trained maximum";

    frequencyHz = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3199000000;
      description = ''
        EMC frequency cap to request from BPMP, in Hz. The default is the
        trained maximum on AGX Orin (and Orin NX). This is a ceiling for
        the demand-driven DVFS governor, not a fixed rate.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.extraModulePackages = [
      (config.boot.kernelPackages.callPackage ./module { })
    ];
    boot.kernelModules = [ "emc_cap_lift" ];
    boot.kernelParams = [ "emc_cap_lift.cap_hz=${toString cfg.frequencyHz}" ];
  };
}
