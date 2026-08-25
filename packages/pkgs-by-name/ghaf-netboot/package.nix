# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  gawk,
  gnugrep,
  gnused,
  iproute2,
  ipxe,
  lib,
  nftables,
  pixiecore,
  python3,
  stdenv,
  writeShellApplication,
}:
let
  # Kept as its own executable rather than a heredoc inside the shell script:
  # writeShellApplication runs shellcheck over its text, and an embedded Python
  # program is both unreadable there and invisible to any Python linting.
  api = python3.pkgs.buildPythonApplication {
    pname = "ghaf-netboot-api";
    version = "0.1.0";
    format = "other";
    src = ./ghaf-netboot-api.py;
    dontUnpack = true;
    installPhase = ''
      install -Dm755 $src $out/bin/ghaf-netboot-api
      patchShebangs $out/bin/ghaf-netboot-api
    '';
  };

  # The iPXE pixiecore embeds drives NICs with iPXE's own native drivers, which
  # on the Lenovo USB-C dock cannot receive broadcast DHCP -- it retries ten
  # times and reboots, and only unplugging the dock clears it. snponly.efi uses
  # the firmware's SNP driver instead, i.e. the same one the firmware's PXE
  # stack uses successfully throughout. See ./boot.ipxe for the other half.
  ghafIpxe =
    (ipxe.override {
      embedScript = ./boot.ipxe;
      # One target, not the usual dozen: this shortens a from-source build we
      # cannot get from a cache, and it keeps the BIOS/ROM outputs we have no use
      # for out of the closure.
      enableDefaultPlatformTargets = false;
      additionalTargets = {
        "bin-x86_64-efi/snponly.efi" = null;
      };
      # Not cosmetic: the ipxe package asserts firmwareBinary is one of the
      # binaries it actually built, and the "ipxe.efirom" default is no longer
      # among them once the default targets are off.
      firmwareBinary = "snponly.efi";
    }).overrideAttrs
      (_: {
        # The ipxe package installs a compatibility symlink undionly.kpxe.0 ->
        # undionly.kpxe on every x86 build, for dnsmasq setups that want the .0
        # suffix. undionly.kpxe is a BIOS target we just switched off, so the
        # link dangles -- and that fails the build outright in fixupPhase, where
        # noBrokenSymlinks treats it as an error rather than a warning.
        postInstall = "rm -f $out/undionly.kpxe.0";
      });

  defaultIpxe = lib.optionalString stdenv.hostPlatform.isx86_64 "${ghafIpxe}/snponly.efi";
in
writeShellApplication {
  name = "ghaf-netboot";
  runtimeInputs = [
    api
    coreutils
    gawk # the interface guard rails, and the cmdline parse out of netboot.ipxe
    gnugrep # --open-firewall, inspecting the nixos-fw set
    gnused # rewriting the builder's cmdline
    iproute2 # ip route / ip addr, for the interface guard rails
    nftables # --open-firewall; PXE is dropped outright without it
    pixiecore # ProxyDHCP + TFTP; never assigns addresses
  ];
  # runtimeEnv, not derivationArgs: the latter sets the variable while the
  # script is *built*, where nothing reads it, and the script then runs with it
  # unset.
  runtimeEnv = {
    GHAF_NETBOOT_IPXE = defaultIpxe;
  };
  text = builtins.readFile ./ghaf-netboot.sh;

  meta = {
    description = "Serve a Ghaf netboot install to one machine on one interface";
    platforms = lib.platforms.linux;
    mainProgram = "ghaf-netboot";
    license = lib.licenses.asl20;
  };
}
