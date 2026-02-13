# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;

  # Importing kernel builder function from packages and checking hardening options
  # TODO: why is the kernek in packages and not in a central place to define the kernels
  buildKernel = import ../kernel-config-builder.nix { inherit config pkgs lib; };
  # TODO: why is the config linked like this? should be available as a module if needed
  config_baseline = ./configs/ghaf_host_hardened_baseline-x86;
  host_hardened_kernel = buildKernel {
    inherit config_baseline;
    host_build = true;
  };

  cfg = config.ghaf.host.kernel.hardening;
in
{
  _file = ./default.nix;

  options.ghaf.host.kernel.hardening = {
    enable = mkEnableOption "Ghaf Host hardening feature";

    virtualization.enable = mkEnableOption "support for virtualization in the Ghaf Host";

    networking.enable = mkEnableOption "support for networking in the Ghaf Host";

    usb.enable = mkEnableOption "support for USB in the Ghaf Host";

    inputdevices.enable = mkEnableOption "support for input devices in the Ghaf Host";

    debug.enable = mkEnableOption "support for debug features in the Ghaf Host";
  };

  config = mkIf pkgs.stdenv.hostPlatform.isx86_64 {
    boot.kernelPackages =
      if cfg.enable then pkgs.linuxPackagesFor host_hardened_kernel else pkgs.linuxPackages_latest;

    # TODO: do we still need this when building our own kernel?
    # https://github.com/NixOS/nixpkgs/issues/109280#issuecomment-973636212
    # TODO: centralize this in a single place for all the overlays
    #nixpkgs.overlays = [
    #  (_final: prev: { makeModulesClosure = x: prev.makeModulesClosure (x // { allowMissing = true; }); })
    #];
  };
}
