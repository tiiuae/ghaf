# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Owner-neutral GPU/display capability payload constructor. Derives the
# vfio-platform device set, guest DT defines, and guest kernel module list
# from a capability descriptor rather than a specific VM's option arm, so
# gpu-vm/disp-vm/gui-vm callers can share one source of truth.
{
  lib,
  ...
}:
let
  capabilities = {
    gpuvm = {
      gpu = true;
      host1x = true;
      media = true;
      display = false;
      noSyncpointDisplay = false;
      memoryLayout = "compute";
    };
    dispvm = {
      gpu = false;
      host1x = false;
      media = false;
      display = true;
      noSyncpointDisplay = true;
      memoryLayout = "display";
    };
    guivm = {
      gpu = true;
      host1x = true;
      media = true;
      display = true;
      noSyncpointDisplay = false;
      memoryLayout = "combined";
    };
  };

  mkPayload =
    cap:
    let
      dropHost1x = !cap.host1x;
      dropDisplay = !cap.display;
      displayOnly = cap.display && !cap.gpu && !cap.host1x;
      computeWithHost1x = cap.gpu && cap.host1x && !cap.display;

      expDtDefines =
        lib.optionalString dropHost1x "-DEXP_DROP_HOST1X "
        + lib.optionalString dropDisplay "-DEXP_DROP_DISPLAY "
        + lib.optionalString displayOnly "-DEXP_DROP_GPU "
        + lib.optionalString computeWithHost1x "-DEXP_SHRINK_BANK1 ";

      # reservedMem: verbatim from gpu-vm/default.nix:54-91, gated on capability booleans
      reservedMem =
        lib.optional cap.host1x {
          dev = "60000000.vm_hs_p";
          base = "0x60000000";
        }
        ++ [
          {
            dev = "80000000.vm_cma_p";
            base = "0x80000000";
          }
          {
            dev = "100000000.vm_cma_vram_p";
            base = "0x100000000";
          }
        ]
        ++ lib.optional (!computeWithHost1x) {
          dev = "b0000000.scanout_p";
          base = "0xb0000000";
        };

      # engines: verbatim from gpu-vm/default.nix:99-108
      engines =
        lib.optional cap.gpu "17000000.gpu"
        ++ lib.optionals cap.host1x [
          "13e00000.host1x_pt"
          "15340000.vic"
          "15480000.nvdec"
          "15540000.nvjpg"
        ];

      # dispCaps: verbatim from gpu-vm/default.nix:124-133
      dispCaps = lib.optionals cap.display [
        {
          dev = "13830000.disp_caps_pt";
          base = "0x66230000";
        }
        {
          dev = "13870000.disp_chan_pt";
          base = "0x66270000";
        }
      ];

      hostDevices = (map (r: r.dev) (reservedMem ++ dispCaps)) ++ engines;

      vfioArgs =
        (lib.concatMap (r: [
          "-device"
          "vfio-platform,host=${r.dev},mmio-base=${r.base}"
        ]) (reservedMem ++ dispCaps))
        ++ (lib.concatMap (d: [
          "-device"
          "vfio-platform,host=${d}"
        ]) engines);

      guestKernelModules =
        lib.optionals cap.host1x [
          "nvmap"
          "host1x"
          "nvhost"
          "nvgpu"
        ]
        ++ lib.optionals cap.display [
          "nvmap"
          "tegra-dce"
          "dce-guest-proxy"
          "nvidia-modeset"
          "nvidia-drm"
        ];
    in
    {
      inherit
        expDtDefines
        hostDevices
        vfioArgs
        guestKernelModules
        ;
      needsDceBridge = cap.display;
      noSyncpointPatch = cap.noSyncpointDisplay;
    };
in
{
  inherit capabilities mkPayload;
}
