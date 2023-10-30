# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.installer;
in {
  options.ghaf.installer = {
    sshKeys = lib.mkOption {
      description = lib.mdDoc "Path to ssh public key that will be used during installation.";
      type = lib.types.listOf lib.types.singleLineStr;
      example = [
        "ssh-rsa AAAAB3NzaC1yc2etc/etc/etcjwrsh8e596z6J0l7 example@host"
        "ssh-ed25519 AAAAC3NzaCetcetera/etceteraJZMfk3QPfQ foo@bar"
      ];
    };
    modules = lib.mkOption {
      description = lib.mdDoc "Modules that will be passed to the installer image.";
      type = with lib.types; listOf deferredModule;
      default = [];
    };
  };

  config.system.build.installer = lib.ghaf.installer {
    inherit (config.nixpkgs.hostPlatform) system;
    inherit (cfg) modules sshKeys;
  };
}
