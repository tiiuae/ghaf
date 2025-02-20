# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Modules that should be only imported to host
#
{ lib, ... }:
{
  networking.hostName = lib.mkDefault "ghaf-host";

  imports = [
    # To push logs to central location
    ../common/logging/client.nix
  ];
}
