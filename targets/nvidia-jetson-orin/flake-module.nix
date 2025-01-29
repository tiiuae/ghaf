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
  inherit (inputs) nixpkgs nixos-generators jetpack-nixos;
  name = "nvidia-jetson-orin";
  system = "aarch64-linux";
  nvidia-jetson-orin =
    som: variant: extraModules:
    let
      netvmExtraModules = [
        {
          # The Nvidia Orin hardware dependent configuration is in
          # modules/reference/hardware/jetpack and modules/reference/hardware/jetpack-microvm. Please refer to that
          # section for hardware dependent netvm configuration.

          # Wireless Configuration. Orin AGX has WiFi enabled where Orin NX does
          # not.

          # To enable or disable wireless
          networking.wireless.enable = som == "agx";

          # For WLAN firmwares
          hardware = {
            enableRedistributableFirmware = som == "agx";
            wirelessRegulatoryDatabase = true;
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
          self.nixosModules.common
          self.nixosModules.desktop
          self.nixosModules.host
          self.nixosModules.jetpack
          self.nixosModules.jetpack-microvm
          self.nixosModules.microvm
          self.nixosModules.reference-programs
          self.nixosModules.reference-personalize

          {
            ghaf = {
              hardware.nvidia.orin = {
                enable = true;
                somType = som;
                agx.enableNetvmWlanPCIPassthrough = som == "agx";
                nx.enableNetvmEthernetPCIPassthrough = som == "nx";
              };

              hardware.nvidia = {
                virtualization.enable = true;
                virtualization.host.bpmp.enable = false;
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
                };
              };

              host.networking.enable = true;

              # Create admin home folder; temporary solution
              users.admin.createHome = true;

              # Enable all the default UI applications
              profiles = {
                applications.enable = true;
                release.enable = variant == "release";
                debug.enable = variant == "debug";
                graphics.renderer = "gles2";
              };
              reference.programs.windows-launcher.enable = true;
              reference.personalize.keys.enable = variant == "debug";

              # To enable screen locking set to true
              graphics.labwc.autolock.enable = false;
            };

            nixpkgs = {
              #TODO: move to a central place for all platforms
              config = {
                allowUnfree = true;
                permittedInsecurePackages = [
                  "jitsi-meet-1.0.8043"
                ];
              };
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
        modules = [ { ghaf.graphics.enableDemoApplications = lib.mkForce false; } ];
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
  mkFlashScript = import ../../lib/mk-flash-script;
  # Generate flash script variant which flashes both QSPI and eMMC
  generate-flash-script =
    tgt: _flash-tools-system:
    mkFlashScript {
      inherit (tgt) hostConfiguration;
    };
  # Generate flash script variant which flashes QSPI only. Useful for Orin NX
  # and non-eMMC based development.
  generate-flash-qspi =
    tgt: _flash-tools-system:
    mkFlashScript {
      hostConfiguration = tgt.hostConfiguration.extendModules {
        modules = [ { ghaf.hardware.nvidia.orin.flashScriptOverrides.onlyQSPI = true; } ];
      };
    };
in
{
  flake = {
    nixosConfigurations = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name t.hostConfiguration) (targets ++ crossTargets)
    );

    packages = {
      aarch64-linux =
        builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets)
        # EXPERIMENTAL: The aarch64-linux hosted flashing support is experimental
        #               and it simply might not work. Providing the script anyway
        // builtins.listToAttrs (
          map (
            t: lib.nameValuePair "${t.name}-flash-script" (generate-flash-script t "aarch64-linux")
          ) targets
        )
        // builtins.listToAttrs (
          map (t: lib.nameValuePair "${t.name}-flash-qspi" (generate-flash-qspi t "aarch64-linux")) targets
        );
      x86_64-linux =
        builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) crossTargets)
        // builtins.listToAttrs (
          map (t: lib.nameValuePair "${t.name}-flash-script" (generate-flash-script t "x86_64-linux")) (
            targets ++ crossTargets
          )
        )
        // builtins.listToAttrs (
          map (t: lib.nameValuePair "${t.name}-flash-qspi" (generate-flash-qspi t "x86_64-linux")) (
            targets ++ crossTargets
          )
        );
    };
  };
}
