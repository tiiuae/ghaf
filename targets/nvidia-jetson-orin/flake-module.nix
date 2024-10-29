# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for NVIDIA Jetson Orin AGX/NX
#
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
  inherit (inputs) nixpkgs jetpack-nixos;
  name = "nvidia-jetson-orin";
  system = "aarch64-linux";

  nvidia-jetson-orin =
    som: variant: extraModules:
    let
      hostConfiguration = lib.nixosSystem {
        inherit system;
        modules = [
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
                # TODO! Disabled for 6.x kernel update, should be fixed and re-enabled!
                # agx.enableNetvmWlanPCIPassthrough = som == "agx";
                # nx.enableNetvmEthernetPCIPassthrough = som == "nx";
              };
              # TODO! Disabled for 6.x kernel update, should be fixed and re-enabled!
              # hardware.nvidia = {
              # virtualization.enable = true;
              # virtualization.host.bpmp.enable = false;
              # passthroughs.host.uarta.enable = false;
              # passthroughs.uarti_net_vm.enable = som == "agx";
              # };
              # virtualization = {
              #   microvm-host = {
              #     enable = true;
              #     networkSupport = true;
              #   };
              #   microvm = {
              #     netvm = {
              #       enable = true;
              #       extraModules = netvmExtraModules;
              #     };
              #   };
              # };
              host.networking.enable = true;
              profiles = {
                # applications.enable = true;
                release.enable = variant == "release";
                debug.enable = variant == "debug";
                graphics.renderer = "gles2";
              };
              # reference.programs.windows-launcher.enable = true;
              reference.personalize.keys.enable = variant == "debug";
              graphics.labwc.autolock.enable = false;
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

  # Base targets
  nvidia-jetson-orin-agx-debug = nvidia-jetson-orin "agx" "debug" [ ];
  nvidia-jetson-orin-agx-release = nvidia-jetson-orin "agx" "release" [ ];
  nvidia-jetson-orin-nx-debug = nvidia-jetson-orin "nx" "debug" [ ];
  nvidia-jetson-orin-nx-release = nvidia-jetson-orin "nx" "release" [ ];

  # Generate nodemoapps variants
  generateNodemoapps =
    tgt:
    let
      hostConfiguration = tgt.hostConfiguration.extendModules {
        modules = [ { ghaf.graphics.enableDemoApplications = lib.mkForce false; } ];
      };
    in
    {
      name = "${tgt.name}-nodemoapps";
      inherit hostConfiguration;
      package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
    };

  nvidia-jetson-orin-agx-debug-nodemoapps = generateNodemoapps nvidia-jetson-orin-agx-debug;
  nvidia-jetson-orin-agx-release-nodemoapps = generateNodemoapps nvidia-jetson-orin-agx-release;
  nvidia-jetson-orin-nx-debug-nodemoapps = generateNodemoapps nvidia-jetson-orin-nx-debug;
  nvidia-jetson-orin-nx-release-nodemoapps = generateNodemoapps nvidia-jetson-orin-nx-release;

  # Generate cross-compilation targets
  generateCrossFromX86_64 =
    tgt:
    let
      hostConfiguration = tgt.hostConfiguration.extendModules { modules = [ ./cross-compilation.nix ]; };
    in
    {
      name = "${tgt.name}-from-x86_64";
      inherit hostConfiguration;
      package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
    };

  nvidia-jetson-orin-agx-debug-from-x86_64 = generateCrossFromX86_64 nvidia-jetson-orin-agx-debug;
  nvidia-jetson-orin-agx-release-from-x86_64 = generateCrossFromX86_64 nvidia-jetson-orin-agx-release;
  nvidia-jetson-orin-nx-debug-from-x86_64 = generateCrossFromX86_64 nvidia-jetson-orin-nx-debug;
  nvidia-jetson-orin-nx-release-from-x86_64 = generateCrossFromX86_64 nvidia-jetson-orin-nx-release;

  nvidia-jetson-orin-agx-debug-nodemoapps-from-x86_64 = generateCrossFromX86_64 nvidia-jetson-orin-agx-debug-nodemoapps;
  nvidia-jetson-orin-agx-release-nodemoapps-from-x86_64 = generateCrossFromX86_64 nvidia-jetson-orin-agx-release-nodemoapps;
  nvidia-jetson-orin-nx-debug-nodemoapps-from-x86_64 = generateCrossFromX86_64 nvidia-jetson-orin-nx-debug-nodemoapps;
  nvidia-jetson-orin-nx-release-nodemoapps-from-x86_64 = generateCrossFromX86_64 nvidia-jetson-orin-nx-release-nodemoapps;

  # Function to generate flash scripts
  mkFlashScript = import ../../lib/mk-flash-script;

  generateFlashScript =
    tgt:
    mkFlashScript {
      inherit nixpkgs;
      inherit (tgt) hostConfiguration;
      inherit jetpack-nixos;
    };

  generateFlashQSPI =
    tgt:
    mkFlashScript {
      inherit nixpkgs;
      hostConfiguration = tgt.hostConfiguration.extendModules {
        modules = [ { ghaf.hardware.nvidia.orin.flashScriptOverrides.onlyQSPI = true; } ];
      };
      inherit jetpack-nixos;
    };

in
{
  flake = {
    nixosConfigurations = {
      # Base configurations
      nvidia-jetson-orin-agx-debug = nvidia-jetson-orin-agx-debug.hostConfiguration;
      nvidia-jetson-orin-agx-release = nvidia-jetson-orin-agx-release.hostConfiguration;
      nvidia-jetson-orin-nx-debug = nvidia-jetson-orin-nx-debug.hostConfiguration;
      nvidia-jetson-orin-nx-release = nvidia-jetson-orin-nx-release.hostConfiguration;

      # Nodemoapps configurations
      nvidia-jetson-orin-agx-debug-nodemoapps = nvidia-jetson-orin-agx-debug-nodemoapps.hostConfiguration;
      nvidia-jetson-orin-agx-release-nodemoapps =
        nvidia-jetson-orin-agx-release-nodemoapps.hostConfiguration;
      nvidia-jetson-orin-nx-debug-nodemoapps = nvidia-jetson-orin-nx-debug-nodemoapps.hostConfiguration;
      nvidia-jetson-orin-nx-release-nodemoapps =
        nvidia-jetson-orin-nx-release-nodemoapps.hostConfiguration;

      # Cross-compilation configurations
      nvidia-jetson-orin-agx-debug-from-x86_64 =
        nvidia-jetson-orin-agx-debug-from-x86_64.hostConfiguration;
      nvidia-jetson-orin-agx-release-from-x86_64 =
        nvidia-jetson-orin-agx-release-from-x86_64.hostConfiguration;
      nvidia-jetson-orin-nx-debug-from-x86_64 = nvidia-jetson-orin-nx-debug-from-x86_64.hostConfiguration;
      nvidia-jetson-orin-nx-release-from-x86_64 =
        nvidia-jetson-orin-nx-release-from-x86_64.hostConfiguration;

      # Cross-compilation nodemoapps configurations
      nvidia-jetson-orin-agx-debug-nodemoapps-from-x86_64 =
        nvidia-jetson-orin-agx-debug-nodemoapps-from-x86_64.hostConfiguration;
      nvidia-jetson-orin-agx-release-nodemoapps-from-x86_64 =
        nvidia-jetson-orin-agx-release-nodemoapps-from-x86_64.hostConfiguration;
      nvidia-jetson-orin-nx-debug-nodemoapps-from-x86_64 =
        nvidia-jetson-orin-nx-debug-nodemoapps-from-x86_64.hostConfiguration;
      nvidia-jetson-orin-nx-release-nodemoapps-from-x86_64 =
        nvidia-jetson-orin-nx-release-nodemoapps-from-x86_64.hostConfiguration;
    };

    packages = {
      aarch64-linux = {
        # Base packages
        nvidia-jetson-orin-agx-debug = nvidia-jetson-orin-agx-debug.package;
        nvidia-jetson-orin-agx-release = nvidia-jetson-orin-agx-release.package;
        nvidia-jetson-orin-nx-debug = nvidia-jetson-orin-nx-debug.package;
        nvidia-jetson-orin-nx-release = nvidia-jetson-orin-nx-release.package;

        # Nodemoapps packages
        nvidia-jetson-orin-agx-debug-nodemoapps = nvidia-jetson-orin-agx-debug-nodemoapps.package;
        nvidia-jetson-orin-agx-release-nodemoapps = nvidia-jetson-orin-agx-release-nodemoapps.package;
        nvidia-jetson-orin-nx-debug-nodemoapps = nvidia-jetson-orin-nx-debug-nodemoapps.package;
        nvidia-jetson-orin-nx-release-nodemoapps = nvidia-jetson-orin-nx-release-nodemoapps.package;
      };

      x86_64-linux = {
        # Cross-compilation packages
        nvidia-jetson-orin-agx-debug-from-x86_64 = nvidia-jetson-orin-agx-debug-from-x86_64.package;
        nvidia-jetson-orin-agx-release-from-x86_64 = nvidia-jetson-orin-agx-release-from-x86_64.package;
        nvidia-jetson-orin-nx-debug-from-x86_64 = nvidia-jetson-orin-nx-debug-from-x86_64.package;
        nvidia-jetson-orin-nx-release-from-x86_64 = nvidia-jetson-orin-nx-release-from-x86_64.package;

        # Cross-compilation nodemoapps packages
        nvidia-jetson-orin-agx-debug-nodemoapps-from-x86_64 =
          nvidia-jetson-orin-agx-debug-nodemoapps-from-x86_64.package;
        nvidia-jetson-orin-agx-release-nodemoapps-from-x86_64 =
          nvidia-jetson-orin-agx-release-nodemoapps-from-x86_64.package;
        nvidia-jetson-orin-nx-debug-nodemoapps-from-x86_64 =
          nvidia-jetson-orin-nx-debug-nodemoapps-from-x86_64.package;
        nvidia-jetson-orin-nx-release-nodemoapps-from-x86_64 =
          nvidia-jetson-orin-nx-release-nodemoapps-from-x86_64.package;

        # Flash scripts (only for x86_64-linux)
        nvidia-jetson-orin-agx-debug-flash-script = generateFlashScript nvidia-jetson-orin-agx-debug;
        nvidia-jetson-orin-agx-release-flash-script = generateFlashScript nvidia-jetson-orin-agx-release;
        nvidia-jetson-orin-nx-debug-flash-script = generateFlashScript nvidia-jetson-orin-nx-debug;
        nvidia-jetson-orin-nx-release-flash-script = generateFlashScript nvidia-jetson-orin-nx-release;

        # Flash scripts for nodemoapps variants
        nvidia-jetson-orin-agx-debug-nodemoapps-flash-script = generateFlashScript nvidia-jetson-orin-agx-debug-nodemoapps;
        nvidia-jetson-orin-agx-release-nodemoapps-flash-script = generateFlashScript nvidia-jetson-orin-agx-release-nodemoapps;
        nvidia-jetson-orin-nx-debug-nodemoapps-flash-script = generateFlashScript nvidia-jetson-orin-nx-debug-nodemoapps;
        nvidia-jetson-orin-nx-release-nodemoapps-flash-script = generateFlashScript nvidia-jetson-orin-nx-release-nodemoapps;

        # Flash QSPI scripts
        nvidia-jetson-orin-agx-debug-flash-qspi = generateFlashQSPI nvidia-jetson-orin-agx-debug;
        nvidia-jetson-orin-agx-release-flash-qspi = generateFlashQSPI nvidia-jetson-orin-agx-release;
        nvidia-jetson-orin-nx-debug-flash-qspi = generateFlashQSPI nvidia-jetson-orin-nx-debug;
        nvidia-jetson-orin-nx-release-flash-qspi = generateFlashQSPI nvidia-jetson-orin-nx-release;

        # Flash QSPI scripts for nodemoapps variants
        nvidia-jetson-orin-agx-debug-nodemoapps-flash-qspi = generateFlashQSPI nvidia-jetson-orin-agx-debug-nodemoapps;
        nvidia-jetson-orin-agx-release-nodemoapps-flash-qspi = generateFlashQSPI nvidia-jetson-orin-agx-release-nodemoapps;
        nvidia-jetson-orin-nx-debug-nodemoapps-flash-qspi = generateFlashQSPI nvidia-jetson-orin-nx-debug-nodemoapps;
        nvidia-jetson-orin-nx-release-nodemoapps-flash-qspi = generateFlashQSPI nvidia-jetson-orin-nx-release-nodemoapps;
      };
    };
  };
}
