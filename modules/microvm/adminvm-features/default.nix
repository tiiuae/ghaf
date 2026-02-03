# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Admin VM Feature Modules
#
# This module aggregates feature modules for the Admin VM and provides
# auto-include logic based on hostConfig.
#
{
  lib,
  hostConfig,
  ...
}:
let
  # Check if any app VM has vTPM enabled (from hostConfig)
  appvmConfig = hostConfig.appvms or { };
  vmsWithVtpm = lib.filterAttrs (
    _: vm: (vm.enable or false) && (vm.vtpm.enable or false) && (vm.vtpm.runInVM or false)
  ) appvmConfig;
  hasVtpmVms = vmsWithVtpm != { };
in
{
  _file = ./default.nix;

  imports = lib.optionals hasVtpmVms [
    ./vtpm-services.nix
  ];
}
