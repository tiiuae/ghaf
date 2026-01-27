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

  nodes.machine =
    { ... }:
    {
      imports = [
        # Only import the modules needed for FSS testing
        ../../modules/common/logging/common.nix
        ../../modules/common/logging/fss.nix
      ];

      # Mock ghaf.type option (used by fss.nix for keyPath)
      options.ghaf.type = lib.mkOption {
        type = lib.types.str;
        default = "host";
      };

      # Mock ghaf.security.audit.extraRules (used by fss.nix)
      options.ghaf.security.audit.extraRules = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
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

        # Ensure persistent journal storage
        services.journald.extraConfig = ''
          Storage=persistent
          Seal=yes
        '';

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

  testScript = _: ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    ${fssSetupTest { }}
    ${fssVerificationTest { }}

    print("All FSS tests completed successfully")
  '';
}
