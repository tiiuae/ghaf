# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{lib, ...}: let
  inherit (lib) mkEnableOption mkOption types literalExpression;

  storageSubmodule = types.submodule {
    options = {
      tag = mkOption {
        type = types.nullOr types.str;
        description = ''
          Storage tag used as label for the microvm share.
        '';
      };
      host-path = mkOption {
        type = types.str;
        description = ''
          Storage directory in the host. If it does not exist, it will be generated
          with the default owner 'microvm' and group 'kvm'.
        '';
      };
      tmp-path = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          (Optional) Temporary directory in the VM to mount the host directory. If this is set,
          the folder from host-path will be recursively copied from 'tmp-path' to 'vm-path' and owner, group,
          and permissions applied.
          If this parameter is null, the host-path is mounted to vm-path directly.
        '';
      };
      vm-path = mkOption {
        type = types.str;
        description = ''
          Storage directory in the guest where the share is mounted to.
        '';
      };
      target-vm = mkOption {
        type = types.str;
        description = ''
          Name of the VM the share is mounted into. The name must match the microvm
          name in 'config.microvm.vms': e.g., "gui-vm" (note the '-').
        '';
      };
      target-owner = mkOption {
        type = types.nullOr types.str;
        description = ''
          Ownership to be applied after copying from 'tmp-path' or passing the files to the vm-path.
          Note that the owner, group, and permissions are applied to the actual host files. This is
          reset on next boot by the host storage service to allow microvm to access the files.
        '';
      };
      target-group = mkOption {
        type = types.nullOr types.str;
        description = ''
          Group to be applied after copying from 'tmp-path' or passing the files to the vm-path.
          Note that the owner, group, and permissions are applied to the actual host files. This is
          reset on next boot by the host storage service to allow microvm to access the files.
        '';
      };
      target-permissions = mkOption {
        type = types.nullOr types.str;
        description = ''
          Permissions to be applied after copying from 'tmp-path' or passing the files to the vm-path.
          Format is an integer string (e.g., "755") as input for chmod.
          Note that the owner, group, and permissions are applied to the actual host files. This is
          reset on next boot by the host storage service to allow microvm to access the files.
        '';
      };
      target-service = mkOption {
        type = types.str;
        default = "default.target";
        description = ''
          Systemd unit that requires the share. If set, the share is processed in the VM before the service is started.
          Defaults to 'default.target'.
        '';
      };
    };
  };
in {
  options.ghaf.services.storage = {
    enable = mkEnableOption "Enable host-to-guest storage module";
    shares = mkOption {
      type = types.listOf storageSubmodule;
      default = [];
      example = literalExpression ''
        [
          {
            tag = "fprint-store";
            host-path = "/var/lib/fprint";
            vm-path = "/var/lib/fprint";
            target-vm = "gui-vm";
            target-owner = "root";
            target-group = "root";
            target-permissions = "600";
            target-service = "fprintd.service";
          }
          {
            tag = "test-store";
            host-path = "/var/testfolder";
            tmp-path = "/var/testfolder";
            vm-path = "/run/testfolder";
            target-vm = "admin-vm";
            target-owner = "ghaf";
            target-group = "ghaf";
            target-permissions = "775";
          }
        ];
      '';
      description = ''
        List of share configurations of type 'storageSubmodule'.
      '';
    };
  };
}
