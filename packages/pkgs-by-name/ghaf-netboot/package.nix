# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  ipxe,
  iproute2,
  lib,
  nftables,
  pixiecore,
  python3,
  writeShellApplication,
}:
let
  # nixpkgs builds bin-x86_64-efi/snp.efi but not snponly.efi, so ask for it.
  # Both land in the same output, which keeps `--ipxe <store>/snp.efi` available
  # as a runtime fallback without another build.
  ipxe' = ipxe.override {
    additionalTargets = {
      "bin-x86_64-efi/snponly.efi" = null;
    };
  };

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
in
writeShellApplication {
  name = "ghaf-netboot";
  runtimeInputs = [
    api
    coreutils
    iproute2 # ip route / ip addr, for the interface guard rails
    nftables # --open-firewall; PXE is dropped outright without it
    pixiecore # ProxyDHCP + TFTP; never assigns addresses
  ];
  text = builtins.readFile ./ghaf-netboot.sh;

  # Deliberately NOT set: pixiecore uses its own embedded iPXE, and that is the
  # only build that works with it.
  # If this is ever set again, it must be runtimeEnv and not derivationArgs --
  # derivationArgs sets the variable while the script is being *built*, where
  # nothing reads it, leaving it unset at runtime.
  passthru.ipxe = ipxe';

  meta = {
    description = "Serve a Ghaf netboot install to one machine on one interface";
    platforms = [ "x86_64-linux" ];
    mainProgram = "ghaf-netboot";
    license = lib.licenses.asl20;
  };
}
