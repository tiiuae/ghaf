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

  orin-configuration = import ./orin-configuration-builder.nix {
    inherit
      lib
      self
      inputs
      jetpack-nixos
      ;
  };

  # setup some commonality between the configurations
  commonModules = [
    (nixos-generators + "/format-module.nix")
    ../../modules/reference/hardware/jetpack/nvidia-jetson-orin/format-module.nix
    jetpack-nixos.nixosModules.default
    #self.nixosModules.microvm
    self.nixosModules.profiles
    self.nixosModules.reference-host-demo-apps
    self.nixosModules.reference-programs
    self.nixosModules.reference-personalize
  ];

  # concatinate modules that are specific to a target
  withCommonModules = specificModules: specificModules ++ commonModules;

  target-configs = [
    # Orin Debug configurations
    (orin-configuration "nvidia-jetson-orin" "agx" "debug" (withCommonModules [
      self.nixosModules.hardware-nvidia-jetson-orin-agx
      {
      }
    ]))
    (orin-configuration "nvidia-jetson-orin" "agx64" "debug" (withCommonModules [
      self.nixosModules.hardware-nvidia-jetson-orin-agx64
      {
      }
    ]))
    (orin-configuration "nvidia-jetson-orin" "nx" "debug" (withCommonModules [
      self.nixosModules.hardware-nvidia-jetson-orin-nx
      {
      }
    ]))

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
                  compositor = "labwc";
                  idleManagement.enable = false;
                  # Disable suspend by default, not working as intended
                  allowSuspend = false;
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
      package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
    };

  generate-cross-from-x86_64 =
    tgt:
    tgt
    // rec {
      name = tgt.name + "-from-x86_64";
      hostConfiguration = tgt.hostConfiguration.extendModules { modules = [ ./cross-compilation.nix ]; };
      package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
    };

  # Add nodemoapps targets
  targets = target-configs ++ (map generate-nodemoapps target-configs);
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
