# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# A wrapper for the givc client CLI. Works in any VM that is part of the ghaf-network.
{
  config,
  pkgs,
  lib,
}:
let
  inherit (lib)
    platforms
    head
    filter
    strings
    optionalString
    ;

  admin = head (filter (x: strings.hasInfix ".100." x.addr) config.ghaf.givc.adminConfig.addresses);

  cliArgs = builtins.replaceStrings [ "\n" ] [ " " ] ''
    --name ${config.ghaf.givc.adminConfig.name}
    --addr ${admin.addr}
    --port ${admin.port}
    ${optionalString config.ghaf.givc.enableTls "--cacert /run/givc/ca-cert.pem"}
    ${optionalString config.ghaf.givc.enableTls "--cert /run/givc/cert.pem"}
    ${optionalString config.ghaf.givc.enableTls "--key /run/givc/key.pem"}
    ${optionalString (!config.ghaf.givc.enableTls) "--notls"}
  '';

  givcCliWrapper = pkgs.writeShellScript "givc-cli-wrapper" ''
    ${pkgs.givc-cli}/bin/givc-cli ${cliArgs} $@
  '';
in
pkgs.stdenv.mkDerivation {
  name = "givc-cli-wrapper";

  phases = [ "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin
    cp ${givcCliWrapper} $out/bin/givc-cli-wrapper
  '';

  meta = {
    description = "Script to launch givc commands via admin service.";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
