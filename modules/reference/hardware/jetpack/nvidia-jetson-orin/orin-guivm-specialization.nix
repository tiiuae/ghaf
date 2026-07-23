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

    # gpu-screen-recorder is x86_64-only (modules/desktop/graphics/screen-recorder.nix
    # asserts pkgs.stdenv.isx86_64). COSMIC's screenRecorder defaults true and maps
    # to ghaf.graphics.screen-recorder.enable, so the aarch64 gui-vm guest would trip
    # that assertion. The Orin host disables it in orin.nix; the guest needs the same.
    ghaf.graphics.cosmic.screenRecorder.enable = lib.mkForce false;

    # Phase 5: pin cosmic-comp to the GA10B render node proven in Phase 4
    # (nvidia-drm on 66200000.display -> renderD128). guivm-base enables
    # cosmic.enable, but renderDevice defaults null (orin.nix's value is
    # host-scope, not inherited by the guest); without it cosmic-comp can't
    # lock the GPU and would fall back to software. By-path node is stable
    # across the card0/card1 (nvdisplay vs host1x) enumeration lottery.
    ghaf.graphics.cosmic.renderDevice =
      lib.mkForce "/dev/dri/by-path/platform-66200000.display-render";

    # Boot/input/TPM/audio specialisation belongs to the later Phase-6 full
    # desktop work.
  };
}
