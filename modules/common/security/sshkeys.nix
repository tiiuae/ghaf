# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  _file = ./sshkeys.nix;

  options.ghaf.security.sshKeys = {
    getAuthKeysFileName = mkOption {
      type = types.str;
      default = "get-auth-keys";
      description = "The name of the get-auth-keys file";
    };
    getAuthKeysFilePathInEtc = mkOption {
      type = types.str;
      default = "ssh/get-auth-keys";
      description = "The path to the SSH host key relative to /etc";
    };
    waypipeSshPublicKeyName = mkOption {
      type = types.str;
      default = "waypipe-ssh-public-key";
      description = "The name of the Waypipe public key";
    };
    waypipeSshPublicKeyDir = mkOption {
      type = types.str;
      default = "/run/waypipe-ssh-public-key";
      description = "The path to the Waypipe public key";
    };
    waypipeSshPublicKeyFile = mkOption {
      type = types.str;
      default = "/run/waypipe-ssh-public-key/id_ed25519.pub";
      description = "The Waypipe public key";
    };
    sshKeyPath = mkOption {
      type = types.str;
      default = "/run/waypipe-ssh/id_ed25519";
      description = "The ssh privatekey";
    };
    sshAuthorizedKeysCommand = mkOption {
      type = types.attrs;
      description = "The authorized_keys command";
      default = {
        authorizedKeysCommand = "/etc/ssh/get-auth-keys";
        authorizedKeysCommandUser = "nobody";
      };
    };
  };
}
