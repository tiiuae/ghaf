# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellScriptBin,
  coreutils,
  config,
}:
# TODO: this really seems to be filthy way to do this.
{
  getAuthKeysSource = {
    source =
      let
        script = writeShellScriptBin config.ghaf.security.sshKeys.getAuthKeysFileName ''
          [[ "$1" != "${config.ghaf.users.appUser.name}" && "$1" != "${config.ghaf.users.admin.name}" ]] && exit 0
          ${coreutils}/bin/cat ${config.ghaf.security.sshKeys.waypipeSshPublicKeyFile}
        '';
      in
      "${script}/bin/${config.ghaf.security.sshKeys.getAuthKeysFileName}";
    mode = "0555";
  };
}
