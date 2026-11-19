# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  isCrosvm = config.microvm.hypervisor == "crosvm";
in
{
  _file = ./vm-crosvm.nix;

  # The host runs THP in madvise mode and crosvm does not advise by default, so guest
  # RAM ends up entirely 4 KiB-backed. --hugepages issues MADV_HUGEPAGE on it.
  microvm.crosvm.extraArgs = lib.optionals isCrosvm [ "--hugepages" ];
}
