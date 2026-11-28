# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM-free check that the live ISOs boot unmodified nixpkgs kernels, which
# cache.nixos.org serves prebuilt.
{
  self,
  lib,
  runCommand,
}:
let
  upstream = self.inputs.nixpkgs.legacyPackages.x86_64-linux;
  bootsKernel = iso: kernel: lib.elem "/boot/${kernel}/bzImage" iso.targets;

  assertions = [
    {
      name = "installer ISO boots the stock linuxPackages_latest kernel";
      ok = bootsKernel self.packages.x86_64-linux.intel-laptop-debug-installer upstream.linuxPackages_latest.kernel;
    }
    {
      name = "laptop-hw-scan ISO boots the stock linuxPackages kernel";
      ok = bootsKernel self.packages.x86_64-linux.laptop-hw-scan upstream.linuxPackages.kernel;
    }
  ];

  failed = map (assertion: assertion.name) (lib.filter (assertion: !assertion.ok) assertions);
in
assert lib.assertMsg (failed == [ ]) "installer stock kernels: ${lib.concatStringsSep "; " failed}";
runCommand "installer-stock-kernels" { } ''touch "$out"''
