# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  ...
}: let
  cfg = config.ghaf.hardware.nvidia.virtualization;
in {
  options.ghaf.hardware.nvidia.virtualization.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Enable virtualization support for NVIDIA Orin

      This option is an implementation level detail and is toggled automatically
      by modules that need it. Manually enabling this option is not recommended in
      release builds.
    '';
  };

  imports = [
    ./common/bpmp-virt-common
    ./host/bpmp-virt-host
    ./host/uarta-host
    ./common/gpio-virt-common
    ./host/gpio-virt-host
  ];
}
