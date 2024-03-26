# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
}: {
  # keygenScript = pkgs.writeShellScriptBin "waypipe-ssh-keygen" ''
  #   set -xeuo pipefail
  #   mkdir -p ${sshPrivateKeyDir}
  #   echo -en "\n\n\n" | ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f ${sshPrivateKeyPath} -C ""
  #   chown ghaf:ghaf ${sshPrivateKeyDir}/*
  #   cp ${sshPrivateKeyDir}/${sshPublicKeyFileName} ${sshPublicKeyDir}/${sshPublicKeyFileName}
  # '';

  getAuthKeysSource = {
    source = let
      script = pkgs.writeShellScriptBin config.ghaf.security.sshKeys.getAuthKeysFileName ''
        [[ "$1" != "ghaf" ]] && exit 0
        ${pkgs.coreutils}/bin/cat ${config.ghaf.security.sshKeys.waypipeSshPublicKeyFile}
      '';
    in "${script}/bin/${config.ghaf.security.sshKeys.getAuthKeysFileName}";
    mode = "0555";
  };
}
