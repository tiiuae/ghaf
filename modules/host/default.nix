# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    # TODO remove this when the minimal config is defined
    # Replace with the baseModules definition
    # UPDATE 26.07.2023:
    # This line breaks build of GUIVM. No investigations of a
    # root cause are done so far.
    #(modulesPath + "/profiles/minimal.nix")

    ../../overlays/custom-packages.nix

    # TODO: Refactor this under virtualization/microvm/host/networking.nix
    ./networking.nix
  ];

  config = {
    networking.hostName = "ghaf-host";
    system.stateVersion = lib.trivial.release;

    ####
    # temp means to reduce the image size
    # TODO remove this when the minimal config is defined
    appstream.enable = false;

    systemd.package = pkgs.systemd.override {
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
    };

    boot.enableContainers = false;
    ##### Remove to here
  };
}
