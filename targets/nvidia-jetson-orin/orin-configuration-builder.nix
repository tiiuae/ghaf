# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  self,
  inputs,
  ...
}:
let
  system = "aarch64-linux";

  #TODO move this to a standalone function
  #should it live in the library or just as a function file
  mkOrinConfiguration =
    name: som: variant: extraModules:
    let
      hostConfiguration = lib.nixosSystem {
        inherit system;
        specialArgs = inputs;
        modules = [
          self.nixosModules.profiles-orin
          {
            hardware.nvidia-jetpack.firmware.uefi.edk2NvidiaPatches = [
              # Jetpack-nixos (at least with HEAD d7631edca76885047fe1df32b00d4224e6a0ad71)
              # enters into boot loop if display is connected to NX/AGX device. NX/AGX with
              # Ghaf boots further, but device crashes when Graphical UI is launched.
              #
              # EDK2-Nvidia has had fixes/workarounds for display related issues. It seems
              # like display handoff does not work properly and therefore for a workaround
              # solution UEFI display is disabled from UEFI config.
              #
              # NOTE: Display stays blank until kernel starts to print. No Nvidia logo,
              # no UEFI menu and no Ghaf splash screen!!
              ./0001-Remove-nvidia-display-config.patch
            ];

            ghaf = {
              profiles = {
                # variant type, turn on debug or release
                debug.enable = variant == "debug";
                release.enable = variant == "release";
              };
            };

            nixpkgs = {
              hostPlatform.system = "aarch64-linux";

              # Increase the support for different devices by allowing the use
              # of proprietary drivers from the respective vendors
              config = {
                allowUnfree = true;
                #jitsi was deemed insecure because of an obsecure potential security
                #vulnerability but it is still used by many people
                permittedInsecurePackages = [
                  "jitsi-meet-1.0.8043"
                  "qtwebengine-5.15.19"
                ];
              };

              overlays = [ self.overlays.default ];
            };
          }
          (import ./optee.nix { })
        ]
        ++ extraModules;
      };
    in
    {
      inherit hostConfiguration;
      inherit variant;
      name = "${name}-${som}-${variant}";
      package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
    };
in
mkOrinConfiguration
