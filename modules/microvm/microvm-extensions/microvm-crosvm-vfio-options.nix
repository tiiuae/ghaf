# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# The pull request https://github.com/microvm-nix/microvm.nix/pull/595 proposes
# to add options for the crosvm runner to configure VFIO passthough devices.
# While or if it is not approved, the following module extends microvm to add
# these configuration options.
#
# This module is more complex than the PR because it can't easily hook into
# microvm internals. We have to inject our logic at the end of the derivation
# build and revert the output produced by microvm that conflicts with the
# new options
#
# microvm.nix only allows pci devices with viommu through its nix module interface.
# Add the option to select the iommu independently per-device.
#
{
  config,
  lib,
  ...
}:
let
  vfioFlagsToRemove = lib.map (
    { path, ... }: "--vfio /sys/bus/pci/devices/${path},iommu=viommu"
  ) config.microvm.devices;

  # While `bus` can only be set to `pci` at the moment, keep the parameter to
  # support platform bus in the future.
  newVfioFlags = lib.concatMap (
    {
      bus,
      path,
      crosvm,
      ...
    }:
    [
      "--vfio"
      (lib.concatStringsSep "," (
        [
          "/sys/bus/${bus}/devices/${path}"
          "iommu=${crosvm.iommu}"
        ]
        ++ lib.optionals (bus == "pci" && crosvm.guestAddress != null) [
          "guest-address=${crosvm.guestAddress}"
        ]
      ))
    ]
  ) config.microvm.devices;
in
{
  options.microvm = with lib; {
    crosvm.vfioIommu = mkOption {
      type =
        with types;
        enum [
          "off"
          "viommu"
          "coiommu"
          "pkvm-iommu"
        ];
      default = "viommu";
      description = ''
        IOMMU type to use by default for VFIO devices.

        This setting will be used as the default for all crosvm microvm.devices definitions.
        The IOMMU type can be set independently for each device via the crosvm.iommu attribute,
        in which case it will take precedence over this option.
      '';
    };

    devices = mkOption {
      type =
        with types;
        listOf (submodule {
          options = {
            bus = mkOption {
              default = "pci";
            };

            crosvm = {
              iommu = mkOption {
                type = nullOr (enum [
                  "off"
                  "viommu"
                  "coiommu"
                  "pkvm-iommu"
                ]);
                default = config.microvm.crosvm.vfioIommu;
                defaultText = lib.literalExpression "config.microvm.crosvm.vfioIommu";
                description = ''
                  IOMMU type to use for this VFIO device (optional)
                '';
              };

              guestAddress = mkOption {
                type = nullOr str;
                default = null;
                description = ''
                  PCI address to use for the VFIO device in the guest.
                  If not specified, defaults to mirroring the host PCI address.
                '';
              };
            };
          };
        });
    };
  };

  config = lib.mkIf (config.microvm.hypervisor == "crosvm" && config.microvm.devices != [ ]) {
    microvm.extraBuildCommands = ''
      ## erase the initial --vfio arguments
      ${lib.concatMapStringsSep "\n" (e: ''
        substituteInPlace "$out/bin/microvm-run" --replace-fail "${e}" ""
      '') vfioFlagsToRemove}
    '';

    microvm.crosvm.extraArgs = newVfioFlags;
  };
}
