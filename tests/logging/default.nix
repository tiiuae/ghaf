# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# NixOS VM Test for Forward Secure Sealing (FSS) Functionality
#
# This test verifies that FSS is properly configured and working. FSS provides
# tamper-evident logging using HMAC-SHA256 chains for systemd journal entries.
#
# To debug interactively, see:
# https://blog.thalheim.io/2023/01/08/how-to-execute-nixos-tests-interactively-for-debugging/
#
# Build and run:
#   nix build .#checks.x86_64-linux.logging-fss
#
# Interactive debugging:
#   nix build .#checks.x86_64-linux.logging-fss.driver
#   ./result/bin/nixos-test-driver
#   # Then in the Python REPL: machine.shell_interact()
#
{
  pkgs,
  lib,
  ...
}:
let
  fssSetupTest = import ./test_scripts/fss_setup.nix;
  fssVerificationTest = import ./test_scripts/fss_verification.nix;
in
pkgs.testers.nixosTest {
  name = "logging-fss";

  nodes.fss =
    { ... }:
    {
      imports = [
        # Only import the modules needed for FSS testing
        ../../modules/common/logging/common.nix
        ../../modules/common/logging/fss.nix
        ../../modules/common/storage-persistence.nix
      ];

      # Mock ghaf options (used by fss.nix for keyPath and audit)
      options.ghaf = {
        type = lib.mkOption {
          type = lib.types.str;
          default = "host";
        };

        security.audit = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          extraRules = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
        };
      };

      config = {
        # Enable FSS with short seal interval for testing
        ghaf.logging.enable = true;
        ghaf.logging.fss = {
          enable = true;
          sealInterval = "1min";
          verifyOnBoot = true;
        };

        networking.hostName = "test-host";

        environment.etc."fss-verify-classifier.sh".text =
          builtins.readFile ../../modules/common/logging/fss-verify-classifier.sh;

        # Create required directories
        systemd.tmpfiles.rules = [
          "d /persist/common/journal-fss 0755 root root - -"
          "d /persist/common/journal-fss/test-host 0700 root root - -"
        ];

        # Test utilities
        environment.systemPackages = with pkgs; [
          coreutils
          gnugrep
          util-linux
        ];
      };
    };

  nodes.statelessVm =
    { ... }:
    {
      imports = [
        ../../modules/common/logging/common.nix
        ../../modules/common/logging/fss.nix
        ../../modules/common/storage-persistence.nix
      ];

      options.ghaf = {
        type = lib.mkOption {
          type = lib.types.str;
          default = "app-vm";
        };

        security.audit = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          extraRules = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
        };
      };

      config = {
        ghaf.logging.enable = true;
        ghaf.storagevm.enable = lib.mkForce false;
        networking.hostName = "stateless-vm";
      };
    };

  testScript = _: ''
    machine = fss
    stateless_vm = statelessVm
    machine.start()
    stateless_vm.start()
    machine.wait_for_unit("multi-user.target")
    stateless_vm.wait_for_unit("multi-user.target")

    with subtest("FSS stays disabled for stateless VMs"):
        stateless_vm.succeed("test ! -e /etc/systemd/system/journal-fss-setup.service")
        stateless_vm.succeed("test ! -e /etc/systemd/system/journal-fss-verify.service")

    ${fssSetupTest { }}
    ${fssVerificationTest { }}

    print("All FSS tests completed successfully")
  '';
}
