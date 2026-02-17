# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for NVIDIA Jetson Orin AGX/NX
#
{
  lib,
  self,
  inputs,
  ...
}:
let
  inherit (inputs) jetpack-nixos;

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
    ../../modules/reference/hardware/jetpack/nvidia-jetson-orin/sdimage.nix
    jetpack-nixos.nixosModules.default
    self.nixosModules.reference-host-demo-apps
    self.nixosModules.reference-profiles-orin
    self.nixosModules.profiles
  ];

  # concatinate modules that are specific to a target
  withCommonModules = specificModules: specificModules ++ commonModules;

  target-configs = [
    # Orin Debug configurations
    (orin-configuration "nvidia-jetson-orin" "agx" "debug" (withCommonModules [
      self.nixosModules.hardware-nvidia-jetson-orin-agx
      {
        ghaf = {
          reference.profiles.mvp-orinuser-trial.enable = true;
        };
      }
    ]))
    (orin-configuration "nvidia-jetson-orin" "agx64" "debug" (withCommonModules [
      self.nixosModules.hardware-nvidia-jetson-orin-agx64
      {
        ghaf = {
          reference.profiles.mvp-orinuser-trial.enable = true;
        };
      }
    ]))
    (orin-configuration "nvidia-jetson-orin" "nx" "debug" (withCommonModules [
      self.nixosModules.hardware-nvidia-jetson-orin-nx
      {
        ghaf = {
          reference.profiles.mvp-orinuser-trial.enable = true;
        };
      }
    ]))

    # Orin Release configurations
    (orin-configuration "nvidia-jetson-orin" "agx" "release" (withCommonModules [
      self.nixosModules.hardware-nvidia-jetson-orin-agx
      {
        ghaf = {
          reference.profiles.mvp-orinuser-trial.enable = true;
        };
      }
    ]))
    (orin-configuration "nvidia-jetson-orin" "agx64" "release" (withCommonModules [
      self.nixosModules.hardware-nvidia-jetson-orin-agx64
      {
        ghaf = {
          reference.profiles.mvp-orinuser-trial.enable = true;
        };
      }
    ]))
    (orin-configuration "nvidia-jetson-orin" "nx" "release" (withCommonModules [
      self.nixosModules.hardware-nvidia-jetson-orin-nx
      {
        ghaf = {
          reference.profiles.mvp-orinuser-trial.enable = true;
        };
      }
    ]))
  ];

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
      package = hostConfiguration.config.system.build.image;
    };

  generate-cross-from-x86_64 =
    tgt:
    tgt
    // rec {
      name = tgt.name + "-from-x86_64";
      hostConfiguration = tgt.hostConfiguration.extendModules { modules = [ ./cross-compilation.nix ]; };
      package = hostConfiguration.config.system.build.image;
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
