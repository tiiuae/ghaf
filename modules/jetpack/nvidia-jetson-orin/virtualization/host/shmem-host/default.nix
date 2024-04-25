# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  ...
}: let
  hugepagesz = 2;
  hugepages = config.ghaf.profiles.applications.ivShMemServer.memSize / hugepagesz;
  hugePagesArg =
    if config.ghaf.profiles.applications.ivShMemServer.enable
    then [
      "hugepagesz=${toString hugepagesz}M"
      "hugepages=${toString hugepages}"
    ]
    else [];
in {
  config = lib.mkIf config.ghaf.profiles.applications.ivShMemServer.enable {
    boot.kernelParams = builtins.trace ">>>>" hugePagesArg;
  };
}
