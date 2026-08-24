# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Thin adapter around microvm.nix's lib.buildRunner. The upstream runner stays
# authoritative; this only changes arguments not yet modeled by microvm.nix.
{
  config,
  lib,
  pkgs,
  microvmFlake,
}:
let
  cfg = config.microvm;
  formatAddress = value: "0x${lib.toLower (lib.toHexString value)}";
  upstreamRunner = microvmFlake.lib.buildRunner {
    inherit pkgs;
    microvmConfig = cfg // {
      inherit (config.networking) hostName;
      hypervisor = "crosvm";
    };
    inherit (config.system.build) toplevel;
  };
  oldMemoryArg = lib.escapeShellArgs [
    "-m"
    (toString cfg.mem)
  ];
  newMemoryArg = lib.escapeShellArgs [
    "--mem"
    "size=${toString cfg.mem},base=${formatAddress cfg.crosvm.memoryBase}"
  ];
  pciSubstitutions = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      path:
      {
        dtSymbol,
        guestAddress,
        iommu,
        ...
      }:
      let
        oldArg = "--vfio /sys/bus/pci/devices/${path},iommu=viommu";
        newArg = lib.escapeShellArgs [
          "--vfio"
          "/sys/bus/pci/devices/${path},iommu=${iommu}${
            lib.optionalString (guestAddress != null) ",guest-address=${guestAddress}"
          }${lib.optionalString (dtSymbol != null) ",dt-symbol=${dtSymbol}"}"
        ];
      in
      ''substituteInPlace "$out/bin/microvm-run" --replace-fail ${lib.escapeShellArg oldArg} ${lib.escapeShellArg newArg}''
    ) cfg.crosvm.pciDeviceOptions
  );
in
pkgs.runCommand "microvm-crosvm-${config.networking.hostName}"
  {
    inherit (upstreamRunner) meta passthru;
  }
  ''
    mkdir -p "$out"
    # Preserve final system and script symlink targets. An extra symlink layer
    # makes the single-readlink comparison in microvm -l report false drift.
    cp -r --no-preserve=mode ${upstreamRunner}/. "$out/"
    rm "$out/bin/microvm-run"
    cp ${upstreamRunner}/bin/microvm-run "$out/bin/microvm-run"
    chmod u+w "$out/bin/microvm-run"
    ${lib.optionalString (cfg.crosvm.memoryBase != null) ''
      substituteInPlace "$out/bin/microvm-run" \
        --replace-fail ${lib.escapeShellArg oldMemoryArg} ${lib.escapeShellArg newMemoryArg}
    ''}
    ${pciSubstitutions}
  ''
