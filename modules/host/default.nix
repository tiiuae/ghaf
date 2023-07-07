# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  microvm,
  netvm,
  guivm,
}: {
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    # TODO remove this when the minimal config is defined
    # Replace with the baseModules definition
    (modulesPath + "/profiles/minimal.nix")

    ../../overlays/custom-packages.nix

    # TODO Refactor the microvm to be fully declarative
    # SEE https://astro.github.io/microvm.nix/declarative.html
    (import ../virtualization/microvm/microvm-host.nix {inherit self microvm netvm guivm;})
    ./networking.nix

    {
      ghaf = {
        virtualization.microvm-host.enable = true;
        host.networking.enable = true;
      };
    }
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
