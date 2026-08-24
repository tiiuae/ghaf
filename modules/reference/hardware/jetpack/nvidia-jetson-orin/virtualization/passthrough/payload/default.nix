# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Owner-neutral GPU/display capability payloads.
{
  lib,
  ...
}:
let
  crosvmLayout = rec {
    memoryBase = lib.fromHexString "0x2000000000";
    platformMmio = {
      base = lib.fromHexString "0x60000000";
      size = memoryBase - platformMmio.base;
    };
  };

  capabilities = {
    gpuvm = {
      gpu = true;
      host1x = true;
      media = true;
      display = false;
      noSyncpointDisplay = false;
    };
    dispvm = {
      gpu = false;
      host1x = false;
      media = false;
      display = true;
      noSyncpointDisplay = true;
    };
    guivm = {
      gpu = true;
      host1x = true;
      media = true;
      display = true;
      # Only display-without-host1x needs the no-syncpoint path.
      noSyncpointDisplay = false;
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

      reservedMem =
        if displayOnly then
          [
            {
              dev = "b0000000.scanout_p";
              base = "0xb0000000";
              size = "0x08000000";
              regCells = "0 b0000000 0 8000000";
              symbol = "scanout_p";
            }
            {
              dev = "b8000000.dispram_lo_p";
              base = "0xb8000000";
              size = "0x2e000000";
              regCells = "0 b8000000 0 2e000000";
              symbol = "dispram_lo_p";
            }
            {
              dev = "200000000.dispram_hi_p";
              base = "0x200000000";
              size = "0x1a000000";
              regCells = "2 0 0 1a000000";
              symbol = "dispram_hi_p";
            }
          ]
        else
          lib.optional cap.host1x {
            dev = "60000000.vm_hs_p";
            base = "0x60000000";
            size = "0x04000000";
            regCells = "0 60000000 0 4000000";
            symbol = "vm_hs_p";
          }
          ++ [
            {
              dev = "80000000.vm_cma_p";
              base = "0x80000000";
              size = "0x30000000";
              regCells = "0 80000000 0 30000000";
              symbol = "vm_cma_p";
            }
          ]
          ++ lib.optional (!computeWithHost1x) {
            dev = "b0000000.scanout_p";
            base = "0xb0000000";
            size = "0x08000000";
            regCells = "0 b0000000 0 8000000";
            symbol = "scanout_p";
          };

      engines =
        lib.optional cap.gpu "17000000.gpu"
        ++ lib.optionals cap.host1x [
          "13e00000.host1x_pt"
          "15340000.vic"
          "15480000.nvdec"
          "15540000.nvjpg"
        ];

      engineSymbols = {
        "17000000.gpu" = "ga10b";
        "13e00000.host1x_pt" = "host1x";
        "15340000.vic" = "vic";
        "15480000.nvdec" = "nvdec";
        "15540000.nvjpg" = "nvjpg";
      };

      # Expose only capability, channel, and cursor keyholes.
      dispCaps = lib.optionals cap.display [
        {
          dev = "13830000.disp_caps_pt";
          base = "0x66230000";
          size = "0x00010000";
          regCells = "0 66230000 0 10000";
          symbol = "disp_caps_pt";
        }
        {
          dev = "13870000.disp_chan_pt";
          base = "0x66270000";
          size = "0x00010000";
          regCells = "0 66270000 0 10000";
          symbol = "disp_chan_pt";
        }
        {
          dev = "138c8000.disp_cursor_pt";
          base = "0x662c8000";
          size = "0x00008000";
          regCells = "0 662c8000 0 8000";
          symbol = "disp_cursor_pt";
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

      crosvmDevices =
        (map (r: {
          path = r.dev;
          dtSymbol = r.symbol;
          iommu = "off";
          mmioBase = lib.fromHexString r.base;
          mapEarly = true;
        }) reservedMem)
        ++ (map (r: {
          path = r.dev;
          dtSymbol = r.symbol;
          iommu = "off";
          mmioBase = lib.fromHexString r.base;
        }) dispCaps)
        ++ (map (d: {
          path = d;
          dtSymbol = engineSymbols.${d};
          iommu = "off";
        }) engines);

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
        reservedMem
        dispCaps
        hostDevices
        vfioArgs
        crosvmDevices
        guestKernelModules
        ;
      needsDceBridge = cap.display;
      noSyncpointPatch = cap.noSyncpointDisplay;
      inherit crosvmLayout;
    };

  # The DCB image is the only board-specific piece; the rest is SoC-level.
  agxBoard = {
    dcbDtsi = "generated/agx-p3737-p3701-dcb.dtsi";
    dcbSha256 = "e0d92e6dbf1ffef266cfd2e192847e76f8d88c19c55430f2f5d4aaf69494a2fc";
    dcbBytes = "8407";
  };
  boards = {
    agx = agxBoard;
    # Stock L4T r36.5 ships one DCB for both devkits (verified against the
    # NX host DTB), so nx aliases agx: one pin to update on a DCB bump.
    nx = agxBoard;
  };
  boardFor = somType: if somType == "nx" then boards.nx else boards.agx;
in
{
  inherit
    capabilities
    crosvmLayout
    mkPayload
    boards
    boardFor
    ;
}
