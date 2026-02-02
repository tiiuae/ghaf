# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Common ghaf modules
#
{ inputs, ... }:
{
  flake.nixosModules = {
    common.imports = [
      ./common.nix
      ./firewall
      ./security
      ./users
      ./version
      ./virtualization
      ./systemd
      ./services
      ./networking
      ./logging
      ./identity
    ];

    # Individual module exports for testing and fine-grained imports
    common-firewall.imports = [ ./firewall ];
    common-security.imports = [ ./security ];
    common-security-fail2ban.imports = [ ./security/fail2ban.nix ];
    common-security-ssh-tarpit.imports = [ ./security/ssh-tarpit ];

    # Cross-compilation module for building aarch64 targets from x86_64
    # This should be included via extendModules when generating
    # cross-compiled variants (e.g., -from-x86_64 builds).
    cross-compilation-from-x86_64 = {
      nixpkgs = {
        buildPlatform.system = "x86_64-linux";
        overlays = [ inputs.self.overlays.cross-compilation ];
      };
    };
  };
}
