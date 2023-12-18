# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.host;
in {
  imports = [
    # TODO: Refactor this under virtualization/microvm/host/networking.nix?
    ./networking.nix
  ];

  options.ghaf.host = {
    enable = lib.mkEnableOption "Enable Ghaf host";
  };

  config = lib.mkIf cfg.enable {
    networking.hostName = "ghaf-host";
    system.stateVersion = lib.trivial.release;

    # TODO should htis be default
    # Also check hot to check if isHostOnly / virt environment
    # To make better descisions on enabling
    ghaf.host.networking.enable = true;

    ####
    # temp means to reduce the image size
    # TODO remove this when the minimal config is defined
    appstream.enable = false;

    systemd.package = pkgs.systemd.override ({
        withCryptsetup = false;
        withDocumentation = false;
        withFido2 = false;
        withHomed = false;
        withHwdb = false;
        withLibBPF = true;
        withLocaled = false;
        withPCRE2 = false;
        withPortabled = false;
        withTpm2Tss = false;
        withUserDb = false;
      }
      // lib.optionalAttrs (lib.hasAttr "withRepart" (lib.functionArgs pkgs.systemd.override)) {
        withRepart = false;
      });

    boot.enableContainers = false;
    ##### Remove to here
  };
}
