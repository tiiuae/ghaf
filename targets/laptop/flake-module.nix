# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for laptop devices based on the hardware and usecase profile
{
  lib,
  self,
  inputs,
  ...
}:
let
  system = "x86_64-linux";

  laptop-configuration = import ./laptop-configuration-builder.nix { inherit lib self inputs; };
  laptop-installer = import ./laptop-installer-builder.nix { inherit lib self inputs; };

  # Modules import structure:
  #
  # - hardware definition module (no enable required)
  #   Contains the hardware definition for the target.
  #
  # - profile module (no enable required)
  #   Contains the profile definition for the target. This module
  #   can make use of ghaf profiles, which import all necessary
  #   dependencies.

  target-configs = [
    # Laptop Debug configurations
    (laptop-configuration "lenovo-x1-carbon-gen10" "debug" [
      self.nixosModules.hardware-lenovo-x1-carbon-gen10
      self.nixosModules.reference-profile-mvp-user-trials
    ])
    (laptop-configuration "lenovo-x1-carbon-gen11" "debug" [
      self.nixosModules.hardware-lenovo-x1-carbon-gen11
      self.nixosModules.reference-profile-mvp-user-trials
    ])
    (laptop-configuration "lenovo-x1-carbon-gen12" "debug" [
      self.nixosModules.hardware-lenovo-x1-carbon-gen12
      self.nixosModules.reference-profile-mvp-user-trials
    ])
    (laptop-configuration "lenovo-x1-extras" "debug" [
      self.nixosModules.hardware-lenovo-x1-carbon-gen11
      self.nixosModules.reference-profile-mvp-user-trials-extras
    ])
    (laptop-configuration "dell-latitude-7230" "debug" [
      self.nixosModules.hardware-dell-latitude-7230
      self.nixosModules.reference-profile-mvp-user-trials
    ])
    (laptop-configuration "dell-latitude-7330" "debug" [
      self.nixosModules.hardware-dell-latitude-7330
      self.nixosModules.reference-profile-mvp-user-trials
    ])
    (laptop-configuration "alienware-m18-R2" "debug" [
      self.nixosModules.hardware-alienware-m18-r2
      self.nixosModules.reference-profile-mvp-user-trials
    ])

    # Laptop Release configurations
    (laptop-configuration "lenovo-x1-carbon-gen10" "release" [
      self.nixosModules.hardware-lenovo-x1-carbon-gen10
      self.nixosModules.reference-profile-mvp-user-trials
    ])
    (laptop-configuration "lenovo-x1-carbon-gen11" "release" [
      self.nixosModules.hardware-lenovo-x1-carbon-gen11
      self.nixosModules.reference-profile-mvp-user-trials
    ])
    (laptop-configuration "lenovo-x1-carbon-gen12" "release" [
      self.nixosModules.hardware-lenovo-x1-carbon-gen12
      self.nixosModules.reference-profile-mvp-user-trials
    ])
    (laptop-configuration "lenovo-x1-extras" "release" [
      self.nixosModules.hardware-lenovo-x1-carbon-gen11
      self.nixosModules.reference-profile-mvp-user-trials-extras
    ])

    (laptop-configuration "dell-latitude-7230" "release" [
      self.nixosModules.hardware-dell-latitude-7230
      self.nixosModules.reference-profile-mvp-user-trials
    ])
    (laptop-configuration "dell-latitude-7330" "release" [
      self.nixosModules.hardware-dell-latitude-7330
      self.nixosModules.reference-profile-mvp-user-trials
    ])
    (laptop-configuration "alienware-m18-R2" "release" [
      self.nixosModules.hardware-alienware-m18-r2
      self.nixosModules.reference-profile-mvp-user-trials
    ])
  ];

  # map all of the defined configurations to an installer image
  target-installers = map (t: laptop-installer t.name t.variant) target-configs;

  targets = target-configs ++ target-installers;
in
{
  flake = {
    nixosConfigurations = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name t.hostConfiguration) targets
    );
    packages.${system} = builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
  };
}
