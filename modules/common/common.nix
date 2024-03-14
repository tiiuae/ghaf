# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# TODO: Refactor even more.
#       This is the old "host/default.nix" file.
{
  lib,
  pkgs,
  ...
}: {
  imports = [
    # TODO remove this when the minimal config is defined
    # Replace with the baseModules definition
    # UPDATE 26.07.2023:
    # This line breaks build of GUIVM. No investigations of a
    # root cause are done so far.
    #(modulesPath + "/profiles/minimal.nix")
  ];

  config = {
    system.stateVersion = lib.trivial.release;

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
    documentation.nixos.enable = false;
    ##### Remove to here
  };
}
