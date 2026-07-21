# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Small AArch64/Orin specialization for the canonical (x86-defaulted) guivm-base.
# Overrides only what guivm-base cannot infer on aarch64.
{ lib, ... }:
{
  _file = ./orin-guivm-specialization.nix;

  # ponytail: guivm-base imports hardware-x86_64-guest-kernel, but that module's
  # entire `config` is `lib.mkIf pkgs.stdenv.hostPlatform.isx86_64 { ... }`
  # (modules/hardware/x86_64-generic/kernel/guest/default.nix), so on aarch64 it
  # evaluates to {} - a no-op. No disabledModules needed; the Jetson combined
  # payload (hardware.definition.guivm.extraModules) sets the real guest kernel.
  config = {
    nixpkgs.hostPlatform = lib.mkForce "aarch64-linux";

    # Guest DT pins four CPUs; keep vcpu in sync (base defaults 6).
    microvm.vcpu = lib.mkForce 4;

    # Renderer/boot/input/TPM/audio specialisation belongs to the hw-bringup
    # plan (Phase 5-6). This module intentionally stays hardware-composition
    # only.
  };
}
