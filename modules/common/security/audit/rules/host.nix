# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isAarch64;
  nixStoreMutationSyscalls =
    if isAarch64 then
      "openat,truncate,renameat,linkat,unlinkat,symlinkat"
    else
      "open,openat,creat,truncate,rename,renameat,link,unlink,unlinkat,symlink";
  # `ghaf.partitioning.verity` may be missing when partitioning modules are not imported.
  verityEnabled = lib.attrByPath [ "ghaf" "partitioning" "verity" "enable" ] false config;
in
lib.optionals config.nix.enable [
  ## === Host :: Nix/NixOS-specific ===
  # Enable Nix tools/state auditing only when Nix is enabled in the target system.
  # Nix profiles & system generations (symlink flips = important)
  "-w /nix/var/nix/profiles -p wa -k nix_profiles"
  # Nix DB & state (writes signal store mutation); keep scope tight to avoid volume
  "-w /nix/var/nix/db -p wa -k nix_db"
  # GC (pinning/unpinning)
  "-w /nix/var/nix/gc.lock -p wa -k nix_gc_lock"
]
++ lib.optionals (config.nix.enable && !verityEnabled) [
  # Keep profile-link watch only for non-verity hosts.
  "-w /nix/var/nix/profiles/system -p wa -k nix_system_host"
]
++ lib.optionals (config.ghaf.security.audit.enableVerboseRebuild && config.nix.enable) [

  ## === Host :: nixos-rebuild ===
  # Nix store modifications
  "-a always,exit -F arch=b64 -S ${nixStoreMutationSyscalls} -F dir=/nix/store -F perm=wa -k nixos_rebuild_store"
]
