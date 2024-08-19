# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ impermanence }:
{ lib, config, ... }:
let
  cfg = config.ghaf.storagevm;
  mountPath = "/tmp/storagevm";
in
{
  imports = [ impermanence.nixosModules.impermanence ];

  options.ghaf.storagevm = with lib; {
    enable = mkEnableOption "StorageVM support";

    name = mkOption {
      description = ''
        Name of the corresponding directory on the storage virtual machine.
      '';
      type = types.str;
    };

    directories = mkOption {
      # FIXME: Probably will lead to disgraceful error messages, as we
      # put typechecking on nix impermanence option. But other,
      # proper, ways are much harder.
      type = types.anything;
      default = [ ];
      example = [
        "Downloads"
        "Music"
        "Pictures"
        "Documents"
        "Videos"
      ];
      description = ''
        Directories to bind mount to persistent storage.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    fileSystems.${mountPath}.neededForBoot = true;

    microvm.shares = [
      {
        tag = "hostshare";
        proto = "virtiofs";
        securityModel = "passthrough";
        source = "/storagevm/${cfg.name}";
        mountPoint = mountPath;
      }
    ];

    environment.persistence.${mountPath} = {
      hideMounts = true;
      inherit (cfg) directories;
      # inherit (cfg) directories;
    };
  };
}
