# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Owner-neutral GPU/display capability payloads.
{
  lib,
  pkgs,
  ...
}:
let
  hardware = pkgs.nvidia-jetpack.orinVirtualizationSupport.passthrough;
  inherit (hardware) crosvmLayout;
  formatAddress = value: "0x${lib.toLower (lib.toHexString value)}";

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
          with hardware.reservedMemory;
          [
            scanout
            dispRamLow
            dispRamHigh
          ]
        else
          lib.optional cap.host1x hardware.reservedMemory.vmHs
          ++ [ hardware.reservedMemory.vmCma ]
          ++ lib.optional (!computeWithHost1x) hardware.reservedMemory.scanout;

      engines =
        lib.optional cap.gpu hardware.engines.gpu
        ++ lib.optionals cap.host1x [
          hardware.engines.host1x
          hardware.engines.vic
          hardware.engines.nvdec
          hardware.engines.nvjpg
        ];

      # Expose only capability, channel, and cursor keyholes.
      dispCaps = lib.optionals cap.display hardware.displayCaps;

      hostDevices = map (device: device.dev) (reservedMem ++ dispCaps ++ engines);

      vfioArgs =
        (lib.concatMap (r: [
          "-device"
          "vfio-platform,host=${r.dev},mmio-base=${formatAddress r.base}"
        ]) (reservedMem ++ dispCaps))
        ++ (lib.concatMap (device: [
          "-device"
          "vfio-platform,host=${device.dev}"
        ]) engines);

      crosvmDevices =
        (map (r: {
          path = r.dev;
          dtSymbol = r.symbol;
          iommu = "off";
          mmioBase = r.base;
          mapEarly = true;
        }) reservedMem)
        ++ (map (r: {
          path = r.dev;
          dtSymbol = r.symbol;
          iommu = "off";
          mmioBase = r.base;
        }) dispCaps)
        ++ (map (device: {
          path = device.dev;
          dtSymbol = device.symbol;
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

in
{
  inherit
    capabilities
    mkPayload
    ;
}
