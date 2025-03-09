# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Modules that should be only imported to host
#
{ lib, ... }:
{
  # TODO Move this and remove this file
  networking.hostName = lib.mkDefault "ghaf-host";
}
