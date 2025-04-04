# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for NVIDIA Jetson Orin AGX/NX
#
{
  inputs,
  lib,
  self,
  ...
}:
let
  inherit (inputs) nixos-generators jetpack-nixos;
  name = "nvidia-jetson-orin";
  system = "aarch64-linux";
  nvidia-jetson-orin =
    som: variant: extraModules:
    let
      netvmExtraModules = [
        {
          # The Nvidia Orin hardware dependent configuration is in
          # modules/reference/hardware/jetpack Please refer to that
          # section for hardware dependent netvm configuration.

          # Wireless Configuration. Orin AGX has WiFi enabled where Orin NX does
          # not.

          # To enable or disable wireless
          networking.wireless.enable = som == "agx";

          # For WLAN firmwares
          hardware = {
            enableRedistributableFirmware = som == "agx";
            wirelessRegulatoryDatabase = som == "agx";
          };

          services.dnsmasq.settings.dhcp-option = [
            "option:router,192.168.100.1" # set net-vm as a default gw
            "option:dns-server,192.168.100.1"
          ];
        }
      ];
      hostConfiguration = lib.nixosSystem {
        inherit system;

        modules = [
          (nixos-generators + "/format-module.nix")
          ../../modules/reference/hardware/jetpack/nvidia-jetson-orin/format-module.nix
          jetpack-nixos.nixosModules.default
          self.nixosModules.jetpack
          self.nixosModules.microvm
          self.nixosModules.profiles
          self.nixosModules.reference-host-demo-apps
          self.nixosModules.reference-programs
          self.nixosModules.reference-personalize

          {
            ghaf = {
              #virtualisation.nvidia-podman.daemon.enable = true;
              virtualisation.nvidia-docker.daemon.enable = true;

              hardware.nvidia.orin = {
                enable = true;
                somType = som;
                agx.enableNetvmWlanPCIPassthrough = som == "agx";
                nx.enableNetvmEthernetPCIPassthrough = som == "nx";
                # Currently we have mostly xavier nx based carrier boards
                carrierBoard = if som == "nx" then "xavierNXdevkit" else "devkit";
              };

              hardware.nvidia = {
                virtualization.enable = true;
                virtualization.host.bpmp.enable = true;
                passthroughs.host.uarta.enable = false;
                # TODO: uarti passthrough is currently broken, it will be enabled
                # later after a further analysis.
                passthroughs.uarti_net_vm.enable = false;
              };

              virtualization = {
                microvm-host = {
                  enable = true;
                  networkSupport = true;
                };

                microvm = {
                  netvm = {
                    enable = true;
                    extraModules = netvmExtraModules;
                  };
                  gpuvm = {
                    enable = true;
                  };
                };
              };

              host.networking.enable = true;

              # Create admin home folder; temporary solution
              users.admin.createHome = true;

              # Enable all the default UI applications
              profiles = {
                graphics = {
                  enable = true;
                  renderer = "gles2";
                  idleManagement.enable = false;
                };
                release.enable = variant == "release";
                debug.enable = variant == "debug";
              };

              reference.programs.windows-launcher.enable = true;
              reference.personalize.keys.enable = variant == "debug";

              reference.host-demo-apps.demo-apps.enableDemoApplications = true;
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
                ];
              };

              overlays = [ self.overlays.default ];
            };
          }

          (import ./optee.nix { })
        ] ++ extraModules;
      };
    in
    {
      inherit hostConfiguration;
      name = "${name}-${som}-${variant}";
      package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
    };
  nvidia-jetson-orin-agx-debug = nvidia-jetson-orin "agx" "debug" [ ];
  nvidia-jetson-orin-agx-release = nvidia-jetson-orin "agx" "release" [ ];
  nvidia-jetson-orin-nx-debug = nvidia-jetson-orin "nx" "debug" [ ];
  nvidia-jetson-orin-nx-release = nvidia-jetson-orin "nx" "release" [ ];

  mkHostImage =
    eval:
    let
      pkg = eval.config.system.build.${eval.config.formatAttr};
    in
    pkg
    // {
      passthru = pkg.passthru or { } // {
        inherit eval;
      };
    };

  generate-nodemoapps =
    tgt:
    tgt
    // rec {
      name = tgt.name + "-nodemoapps";
      hostConfiguration = tgt.hostConfiguration.extendModules {
        modules = [
          { ghaf.reference.host-demo-apps.demo-apps.enableDemoApplications = lib.mkForce false; }
        ];
      };
      package = mkHostImage hostConfiguration;
    };
  generate-cross-from-x86_64 =
    tgt:
    tgt
    // rec {
      name = tgt.name + "-from-x86_64";
      hostConfiguration = tgt.hostConfiguration.extendModules { modules = [ ./cross-compilation.nix ]; };
      package = mkHostImage hostConfiguration;
    };
  # Base targets to use for generating demoapps and cross-compilation targets
  baseTargets = [
    nvidia-jetson-orin-agx-debug
    nvidia-jetson-orin-agx-release
    nvidia-jetson-orin-nx-debug
    nvidia-jetson-orin-nx-release
  ];
  # Add nodemoapps targets
  targets = baseTargets ++ (map generate-nodemoapps baseTargets);
  crossTargets = map generate-cross-from-x86_64 targets;
in
{
  flake = {
    nixosConfigurations = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name t.hostConfiguration) (targets ++ crossTargets)
    );

    packages = {
      aarch64-linux = builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
      x86_64-linux =
        builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) crossTargets)
        // builtins.listToAttrs (
          map (
            t: lib.nameValuePair "${t.name}-flash-script" t.hostConfiguration.pkgs.nvidia-jetpack.flashScript
          ) crossTargets
        )
        // builtins.listToAttrs (
          map (
            t:
            lib.nameValuePair "${t.name}-flash-qspi"
              (t.hostConfiguration.extendModules {
                modules = [ { ghaf.hardware.nvidia.orin.flashScriptOverrides.onlyQSPI = true; } ];
              }).pkgs.nvidia-jetpack.flashScript
          ) crossTargets
        );
    };
  };
}
