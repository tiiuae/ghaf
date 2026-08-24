# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ self, ... }:
{
  flake.checks =
    let
      pkgsPerSystem = system: self.inputs.nixpkgs.legacyPackages.${system};
    in
    {
      x86_64-linux =
        let
          pkgs = (pkgsPerSystem "x86_64-linux").extend (
            self.inputs.nixpkgs.lib.composeManyExtensions [
              self.overlays.default
              (_: _prev: { inherit (self) lib; })
            ]
          );
        in
        {
          installer = pkgs.callPackage ./installer { inherit self; };
          netboot-boot = pkgs.callPackage ./installer/netboot-boot.nix { inherit self; };
          netboot-fetch = pkgs.callPackage ./installer/netboot-fetch.nix { inherit self; };
          netboot-server = pkgs.callPackage ./installer/netboot-server.nix { inherit self; };
          # Still disabled, but for one well-understood reason rather than two.
          #
          # It used to fail before booting: firewall.nix grew a reference to
          # ghaf.givc.policyClient and the test node never declared it. That is
          # fixed (see givcOptionStub in ./firewall), so the test now builds,
          # boots and runs.
          #
          # What remains is a real behavioural disagreement, not a test-side
          # bug. `basic_rules` pings 20 times and expects 15 drops -- ICMP
          # rate-limited past a burst of 5 -- but firewall.nix:506 now accepts
          # all new ICMP unconditionally, so nothing is dropped and it counts 0.
          # Whether ICMP should be rate-limited is a security decision for
          # whoever made that change; the test should not simply be relaxed to
          # match. Re-enable once that is settled.
          # firewall = pkgs.callPackage ./firewall { inherit self; };
          cosmic-panels = pkgs.callPackage ./cosmic/panels.nix { inherit self; };
          cosmic-shortcuts = pkgs.callPackage ./cosmic/shortcuts.nix { inherit self; };
          flatpak-options = pkgs.callPackage ./flatpak/options.nix { inherit self; };
          microvm-tpm-vmm-parity = pkgs.callPackage ./microvm/tpm-vmm-parity.nix { inherit self; };
          uplink-resolver = pkgs.callPackage ./uplink-resolver { };
          logging-fss = pkgs.callPackage ./logging { inherit self; };
          logging-logseald = pkgs.callPackage ./logseald { inherit self; };
          fss-classifier-unit = pkgs.callPackage ./logging/classifier-unit.nix { };
          fss-test = pkgs.callPackage ./logging/test_scripts/fss-test.nix { };
          fss-triage = pkgs.callPackage ./logging/test_scripts/fss-triage.nix { };
          access-control-tests = pkgs.callPackage ./access-control { inherit self; };
        };
    };
}
