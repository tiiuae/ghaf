# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  self,
  lib,
  microvm,
  lanzaboote,
  name,
  system,
  ...
}: let
  lenovo-x1 = generation: variant: extraModules: let
    hostConfiguration = lib.nixosSystem {
      inherit system;
      modules =
        [
          lanzaboote.nixosModules.lanzaboote
          microvm.nixosModules.host
          self.nixosModules.common
          self.nixosModules.desktop
          self.nixosModules.host
          self.nixosModules.lanzaboote
          self.nixosModules.microvm
          self.nixosModules.reference-appvms
          self.nixosModules.reference-programs
          self.nixosModules.reference-services

          ({
            pkgs,
            config,
            ...
          }: let
            powerControl = pkgs.callPackage ../../packages/powercontrol {};
          in {
            security.polkit = {
              enable = true;
              extraConfig = powerControl.polkitExtraConfig;
            };
            time.timeZone = "Asia/Dubai";

            ghaf = {
              # variant type, turn on debug or release
              profiles = {
                debug.enable = variant == "debug";
                release.enable = variant == "release";
              };

              # Hardware definitions
              hardware = {
                inherit generation;
                x86_64.common.enable = true;
                tpm2.enable = true;
                usb.internal.enable = true;
                usb.external.enable = true;
              };

              # TODO: move this to module
              services.fprint.enable = true;

              reference.appvms = {
                enable = true;
                chromium-vm = true;
                gala-vm = true;
                zathura-vm = true;
                element-vm = true;
                appflowy-vm = true;
              };

              reference.services = {
                enable = true;
                dendrite = true;
              };

              # Virtualization options
              virtualization = {
                microvm-host = {
                  enable = true;
                  networkSupport = true;
                };

                microvm = {
                  netvm = {
                    enable = true;
                    wifi = true;
                    extraModules = [self.nixosModules.reference-services];
                  };

                  adminvm = {
                    enable = true;
                  };

                  idsvm = {
                    enable = false;
                    mitmproxy.enable = false;
                  };

                  guivm = {
                    enable = true;
                    extraModules =
                      # TODO convert this to an actual module
                      import ./guivmExtraModules.nix {
                        inherit lib pkgs self;
                        configH = config;
                      };
                  };

                  audiovm = {
                    enable = true;
                    audio = true;
                  };

                  appvm = {
                    enable = true;
                    vms = config.ghaf.reference.appvms.enabled-app-vms;
                  };
                };
              };

              host = {
                networking.enable = true;
                powercontrol.enable = true;
              };

              # UI applications
              profiles = {
                applications.enable = false;
              };

              windows-launcher = {
                enable = true;
                spice = true;
              };
            };
          })
        ]
        ++ extraModules;
    };
  in {
    inherit hostConfiguration;
    name = "${name}-${generation}-${variant}";
    package = hostConfiguration.config.system.build.diskoImages;
  };
in [
  (lenovo-x1 "gen10" "debug" [self.nixosModules.disko-lenovo-x1-basic-v1 self.nixosModules.hw-lenovo-x1])
  (lenovo-x1 "gen11" "debug" [self.nixosModules.disko-lenovo-x1-basic-v1 self.nixosModules.hw-lenovo-x1])
  (lenovo-x1 "gen10" "release" [self.nixosModules.disko-lenovo-x1-basic-v1 self.nixosModules.hw-lenovo-x1])
  (lenovo-x1 "gen11" "release" [self.nixosModules.disko-lenovo-x1-basic-v1 self.nixosModules.hw-lenovo-x1])
]
