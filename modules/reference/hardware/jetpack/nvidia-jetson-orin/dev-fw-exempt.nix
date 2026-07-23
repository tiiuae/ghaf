# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Dev-only relaxation of net-vm's ssh flood ban.
#
# net-vm runs ghaf.firewall.attack-mitigation, which blacklists a source IP
# after burst 5 / 30-per-minute ssh connections (-> ghaf-fw-blacklist-add ->
# DROP for ~an hour). `nix copy` opens several parallel ssh streams and repeated
# dev ssh/deploy loops trip it instantly, banning the dev host (see
# orin-guivm-flash-blocker-handoff.md — it cost most of a bring-up session).
#
# The firewall deliberately forbids `-j ACCEPT` in its extra hooks, so a
# per-IP allowlist is not possible; instead raise the flood thresholds well
# above what a dev workflow produces. DEV ONLY — do not enable in production.
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.dev.firewallExempt;
in
{
  _file = ./dev-fw-exempt.nix;

  options.ghaf.dev.firewallExempt.relaxSshFlood =
    lib.mkEnableOption "relax net-vm's ssh flood rate-limit for dev (nix copy / deploy bursts self-ban otherwise)";

  config = lib.mkIf cfg.relaxSshFlood {
    # Default is burst 5 / 30-per-minute — nix copy's parallel streams exceed it
    # at once. Raise it high enough that dev bursts pass while a real flood is
    # still bounded.
    ghaf.firewall.attack-mitigation.ssh.rule = lib.mkForce {
      burstNum = 100;
      maxPacketFreq = "1000/minute";
    };
  };
}
