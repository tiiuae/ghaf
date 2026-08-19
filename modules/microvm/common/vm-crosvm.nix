# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  isCrosvm = config.microvm.hypervisor == "crosvm";
in
{
  _file = ./vm-crosvm.nix;

  # Crosvm's serial console makes systemd's per-unit shutdown status output
  # expensive. The messages remain available in the guest journal; suppressing
  # only their console rendering avoids adding seconds to every guest shutdown.
  systemd.settings.Manager.ShowStatus = lib.mkIf isCrosvm false;

  # Crosvm's virtual IOMMU must be available before PCI enumeration.  Loading
  # it as a module lets passthrough drivers race ahead of the IOMMU supplier;
  # the late registration then leaves those devices without an IOMMU group and
  # DMA-backed drivers cannot probe reliably.
  boot.kernelPatches = lib.optionals (isCrosvm && pkgs.stdenv.hostPlatform.isx86_64) [
    {
      name = "crosvm-virtio-iommu-builtin";
      patch = null;
      structuredExtraConfig = with lib.kernel; {
        VIRTIO = yes;
        VIRTIO_PCI = yes;
        VIRTIO_IOMMU = yes;
      };
    }
  ];
}
