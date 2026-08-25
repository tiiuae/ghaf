# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  bpmpHostPath,
  crosvmOverlay,
  dtb,
  payload,
  role,
}:
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  isCrosvm = config.microvm.hypervisor == "crosvm";
in
{
  imports = [ inputs.jetpack-nixos.nixosModules.orin-virtualization ];

  hardware.nvidia-jetpack.virtualization.gpuPassthroughGuest = {
    enable = true;
    inherit role;
  };

  systemd.services.ghaf-crosvm-poweroff = lib.mkIf isCrosvm {
    description = "Power off the Orin Crosvm guest";
    serviceConfig.Type = "oneshot";
    script = ''
      ${lib.getExe' pkgs.systemd "systemctl"} start --no-block poweroff.target
    '';
  };
  givc.sysvm = lib.mkMerge [
    { capabilities.services = lib.optionals isCrosvm [ "ghaf-crosvm-poweroff.service" ]; }
    (lib.mkIf (isCrosvm && !(payload.capabilities.gpu && payload.capabilities.display)) {
      enable = true;
      inherit (config.ghaf.givc) debug;
      network = {
        agent.transport = {
          name = config.networking.hostName;
          addr = config.ghaf.networking.hosts.${config.networking.hostName}.ipv4;
          port = "9000";
        };
        tls.enable = config.ghaf.givc.enableTls;
        admin.transport = lib.head config.ghaf.givc.adminConfig.addresses;
      };
    })
  ];

  ghaf.virtualization.qemu.package = lib.mkIf (!isCrosvm) (
    lib.mkForce pkgs.ghaf-nvidia-qemu-bpmp-gpu
  );

  assertions = lib.optionals isCrosvm [
    {
      assertion = map (device: device.path) payload.crosvmDevices == payload.hostDevices;
      message = "Orin Crosvm GPU/display device order drifted from its allocation layout.";
    }
  ];

  microvm = lib.mkMerge [
    {
      qemu.extraArgs = lib.mkIf (!isCrosvm) (
        [
          "-dtb"
          "${dtb}/${payload.dtbName}"
        ]
        ++ payload.vfioArgs
      );
    }
    (lib.mkIf isCrosvm {
      devices = map (
        {
          path,
          dtSymbol,
          iommu,
          mmioBase ? null,
          mapEarly ? false,
        }:
        {
          bus = "platform";
          inherit path;
          crosvm = {
            inherit
              dtSymbol
              iommu
              mmioBase
              mapEarly
              ;
          };
        }
      ) payload.crosvmDevices;
      crosvm = {
        inherit (payload.crosvmLayout) memoryBase platformMmio;
        deviceTreeOverlays = [ "${crosvmOverlay}/${crosvmOverlay.fileName}" ];
        extraArgs = [
          "--nvidia-bpmp-host"
          bpmpHostPath
        ]
        ++ lib.optionals payload.needsDceBridge [
          "--nvidia-dce-host"
          "/dev/dce-host"
        ];
      };
    })
  ];
}
