# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Expands targets/machines.nix into nixosConfigurations and packages.
#
# No product or hardware decisions belong here. A `ghaf.*` line in this file
# belongs either in a reference profile or in modules/reference/hardware/.
{
  lib,
  self,
  inputs,
  ...
}:
let
  system = "x86_64-linux";

  ghaf-configuration = self.builders.mkGhafConfiguration {
    inherit self inputs;
    inherit (self) lib;
  };

  # One installer system, shared by every target's ISO.
  ghaf-installer = self.builders.mkGhafInstaller {
    inherit self system;
    inherit (self) lib;
    extraModules = installerModules;
  };

  ghaf-netboot-installer = self.builders.mkGhafNetbootInstaller {
    inherit self system;
    inherit (self) lib;
    extraModules = installerModules;
  };

  commonModules = [
    self.nixosModules.disko-debug-partition
    self.nixosModules.verity-release-partition
    self.nixosModules.reference-profiles
    self.nixosModules.profiles
  ];

  # Everything the installer environment needs beyond the boot medium: the dev
  # SSH keys and the Secure Boot enrollment keys.
  installerModule =
    { config, ... }:
    {
      imports = [
        self.nixosModules.common
        self.nixosModules.givc
        self.nixosModules.development
        self.nixosModules.reference-personalize
      ];

      ghaf.host.secureboot.enable = true;

      users.users.nixos.openssh.authorizedKeys.keys =
        config.ghaf.reference.personalize.keys.authorizedSshKeys;
    };

  installerModules = [ installerModule ];

  machines = import ./machines.nix;
  axes = import ./axes.nix;

  # Power set, each subset keeping declaration order. Axes sharing a `group` are
  # mutually exclusive, so subsets naming two of them are dropped.
  subsets =
    names:
    let
      powerSet = lib.foldl' (acc: x: acc ++ map (s: s ++ [ x ]) acc) [ [ ] ] names;
      groupsOf = s: lib.filter (g: g != null) (map (a: axes.${a}.group or null) s);
    in
    lib.filter (
      s:
      let
        g = groupsOf s;
      in
      g == lib.unique g
    ) powerSet;

  mkTarget =
    name: machine: variant: axisNames:
    let
      picked = map (a: axes.${a}) axisNames;
      merge = f: lib.foldl' lib.recursiveUpdate { } (map (a: a.${f} or { }) picked);
    in
    ghaf-configuration {
      name = name + lib.concatMapStrings (a: a.suffix) picked;
      inherit system variant;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules."hardware-${machine.hardware}";
      extraModules = commonModules;
      # A/B update images cover the axis-free target only, so adding an axis to a
      # machine does not multiply the verity image count.
      buildSysupdateImage = (machine.sysupdate or false) && picked == [ ];
      extraConfig = lib.recursiveUpdate {
        reference.profiles.${machine.product or "mvp-user-trial"}.enable = true;
        partitioning.disko.enable = true;
      } (merge "config");
      vmConfig = merge "vmConfig";
    };

  target-configs = lib.concatLists (
    lib.mapAttrsToList (
      name: machine:
      lib.concatMap (
        variant: map (mkTarget name machine variant) (subsets (machine.axes or [ ]))
      ) machine.variants
    ) machines
  );

  # Secure A/B is deliberately an additive target family: legacy laptop names
  # and artifacts remain unchanged while the trust and rollback contract is
  # validated. Only axis-free targets that already opted into sysupdate are
  # candidates, avoiding a combinatorial copy of platform-independent logic.
  secure-targets = map (
    t:
    let
      secureName = "${t.name}-secure-ab";
    in
    (t.extendHost [
      self.nixosModules.secure-ab-x86
      {
        ghaf = {
          secureUpdate = {
            enable = true;
            target = secureName;
          };
          partitioning.verity = {
            enable = true;
            initialDisk.enable = true;
          };
          boot-health.enable = true;
        };
      }
    ])
    // {
      name = secureName;
    }
  ) (builtins.filter (x: x.buildSysupdateImage) target-configs);

  # Map all of the defined configurations to an installer image. Each installer
  # reuses the shared base NixOS evaluation and only overrides ISO contents.
  target-installers = map (
    t:
    ghaf-installer {
      inherit (t) name;
      imagePath = self.packages.x86_64-linux.${t.name};
    }
  ) target-configs;

  # Netboot counterparts. Unlike the ISOs these do NOT depend on the disk image
  # -- it is fetched at install time -- so they are tiny and share one kernel
  # and initrd across every target.
  target-netboot-installers = map (t: ghaf-netboot-installer { inherit (t) name; }) target-configs;

  target-sysupdates = map (
    t:
    (t.extendHost [
      {
        ghaf.partitioning.verity.enable = true;
      }
    ])
    // {
      name = "${t.name}-sysupdate";
    }
  ) (builtins.filter (x: x.buildSysupdateImage) target-configs);

  secure-sysupdates = map (
    t:
    (t.extendHost [
      {
        ghaf = {
          partitioning.verity.initialDisk.enable = lib.mkForce false;
        };
        boot.uki.tries = 3;
      }
    ])
    // {
      name = "${t.name}-sysupdate";
    }
  ) secure-targets;

  config-targets = target-configs ++ target-sysupdates ++ secure-targets ++ secure-sysupdates;
  package-targets =
    target-configs
    ++ target-installers
    ++ target-netboot-installers
    ++ target-sysupdates
    ++ secure-targets
    ++ secure-sysupdates;
in
{
  flake = {
    # So tests can build the installer the targets actually ship. See the
    # comment on installerModule above.
    nixosModules.laptop-installer = installerModule;

    nixosConfigurations = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name t.hostConfiguration) config-targets
    );
    packages.${system} = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name t.package) package-targets
    );
  };
}
