# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  runCommand,
}:
let
  orinTargets = lib.filterAttrs (
    name: _: lib.hasPrefix "nvidia-jetson-orin-" name
  ) self.nixosConfigurations;
  # Nodemoapps, LUKS, UKI, and cross variants only extend these base targets.
  # Check the bases here; the eval and build matrices exercise every variant.
  baseTargetNames = [
    "nvidia-jetson-orin-agx-debug"
    "nvidia-jetson-orin-agx-release"
    "nvidia-jetson-orin-agx-industrial-debug"
    "nvidia-jetson-orin-agx-industrial-release"
    "nvidia-jetson-orin-agx-verity-debug"
    "nvidia-jetson-orin-agx-verity-release"
    "nvidia-jetson-orin-agx-verity-luks-debug"
    "nvidia-jetson-orin-agx64-debug"
    "nvidia-jetson-orin-agx64-release"
    "nvidia-jetson-orin-nx-debug"
    "nvidia-jetson-orin-nx-release"
    "nvidia-jetson-orin-nx-verity-luks-debug"
  ];
  baseTargets = lib.getAttrs baseTargetNames orinTargets;
  hostConfig = target: target.config;
  vmConfigs = host: map (vm: vm.evaluatedConfig.config) (builtins.attrValues host.microvm.vms);
  usesCrosvm = host: lib.all (vm: vm.microvm.hypervisor == "crosvm") (vmConfigs host);

  targetAssertions = lib.mapAttrsToList (
    name: target:
    let
      host = hostConfig target;
    in
    {
      inherit name;
      ok =
        host.ghaf.hardware.nvidia.orin.crosvm.enable
        && host.ghaf.virtualization.vmConfig.defaultSysVmVmm == "crosvm"
        && host.ghaf.virtualization.vmConfig.defaultAppVmVmm == "crosvm"
        && host.ghaf.hardware.passthrough.deviceManager.backend == "ghaf-device-manager"
        && host.ghaf.hardware.nvidia.passthroughs.gui_vm.enable
        && host.ghaf.hardware.nvidia.passthroughs.mttcan_net_vm.enable
        && host.hardware.nvidia-jetpack.virtualization.mttcanHost.enable
        && host.ghaf.virtualization.microvm.guivm.enable
        && !host.ghaf.profiles.graphics.enable
        && !host.ghaf.graphics.cosmic.enable
        &&
          host.hardware.nvidia-jetpack.virtualization.gpuPassthroughHost.assignments == {
            gui-vm.role = "combined";
          }
        && host.microvm.vms ? "gui-vm"
        && (
          !lib.hasPrefix "nvidia-jetson-orin-nx-" name
          || host.microvm.vms.gui-vm.evaluatedConfig.config.microvm.mem == 4096
        )
        && usesCrosvm host
        && lib.all (
          vm:
          !vm.ghaf.virtualization.microvm.tpm.emulated.enable
          || (
            lib.elem "tpm_virtio" vm.boot.initrd.kernelModules
            && lib.any (
              patch:
              patch.name == "chromiumos-virtio-tpm"
              && patch.structuredExtraConfig.TCG_VIRTIO_VTPM == lib.kernel.module
            ) vm.boot.kernelPatches
          )
        ) (vmConfigs host)
        && host.systemd.services ? ghaf-device-manager
        && !(host.systemd.services ? vhotplug);
    }
  ) baseTargets;

  agx = hostConfig baseTargets.nvidia-jetson-orin-agx-release;
  agxNetVm = agx.microvm.vms."net-vm".evaluatedConfig.config;
  agxNetService = agx.systemd.services."microvm@net-vm";
  nx = hostConfig baseTargets.nvidia-jetson-orin-nx-debug;
  nxNetVm = nx.microvm.vms."net-vm".evaluatedConfig.config;
  nxNetService = nx.systemd.services."microvm@net-vm";
  nxPlatformDevices = lib.filter (device: device.bus == "platform") nxNetVm.microvm.devices;
  nxMttcanDevices = lib.filter (device: lib.hasSuffix ".mttcan" device.path) nxPlatformDevices;
  nxMttcanModulePackages = lib.filter (
    package: (package.pname or "") == "l4t-mttcan-modules"
  ) nxNetVm.boot.extraModulePackages;
  nxGuiShutdown = nx.systemd.services."ghaf-crosvm-shutdown-gui-vm";
  nxGuiShutdownScript = nxGuiShutdown.serviceConfig.ExecStop;
  splitAgx =
    (baseTargets.nvidia-jetson-orin-agx-debug.extendModules {
      modules = [
        self.nixosModules.jetpack-orin-gpu-partitioning
        {
          ghaf.org.identity.ssh.trustedUserCAKeys = [ "ssh-ed25519 AAAATESTKEY orin-crosvm-test" ];
          ghaf.hardware.nvidia.passthroughs = {
            gui_vm.enable = lib.mkForce false;
            gpu_vm.enable = true;
            disp_vm.enable = true;
          };
        }
      ];
    }).config;
  splitNx =
    (baseTargets.nvidia-jetson-orin-nx-debug.extendModules {
      modules = [
        self.nixosModules.jetpack-orin-gpu-partitioning
        {
          ghaf.hardware.nvidia.passthroughs = {
            gui_vm.enable = lib.mkForce false;
            gpu_vm.enable = true;
            disp_vm.enable = true;
          };
        }
      ];
    }).config;
  splitVmConfigs = map (vm: vm.evaluatedConfig.config) (builtins.attrValues splitAgx.microvm.vms);
  qemuFallback =
    (baseTargets.nvidia-jetson-orin-agx-release.extendModules {
      modules = [
        {
          ghaf.virtualization.vmConfig = {
            defaultSysVmVmm = lib.mkForce "qemu";
            defaultAppVmVmm = lib.mkForce "qemu";
          };
        }
      ];
    }).config;

  assertions = targetAssertions ++ [
    {
      name = "CAN tools ship only in debug NetVMs";
      ok = lib.all (
        target:
        let
          guest = target.config.microvm.vms.net-vm.evaluatedConfig.config;
        in
        lib.any (package: (package.pname or "") == "can-utils") guest.environment.systemPackages
        == guest.ghaf.profiles.debug.enable
      ) (builtins.attrValues baseTargets);
    }
    {
      name = "NX CAN preserves the default kernel and NetVM cannot control SoC memory bandwidth";
      ok =
        nxNetVm.boot.kernelPackages.kernel.version
        == baseTargets.nvidia-jetson-orin-nx-debug.pkgs.linuxPackages.kernel.version
        && !nx.hardware.nvidia-jetpack.virtualization.bpmpHost.consumers.net-vm.allowMemoryControl
        && !agx.hardware.nvidia-jetpack.virtualization.bpmpHost.consumers.net-vm.allowMemoryControl;
    }
    {
      name = "CAN shutdown is ordered and tolerates unprobed controllers";
      ok =
        lib.all
          (
            guest:
            let
              unit = guest.systemd.services.quiesce-mttcan;
            in
            lib.hasPrefix "-" unit.serviceConfig.ExecStop
            && lib.elem "NetworkManager.service" unit.after
            && lib.elem "givc-net-vm.service" unit.after
          )
          [
            nxNetVm
            agxNetVm
          ];
    }
    {
      name = "QEMU rollback warns that CAN passthrough is unavailable";
      ok = lib.any (
        warning: lib.hasInfix "Orin MTTCAN passthrough requires Crosvm" warning
      ) qemuFallback.warnings;
    }
    {
      name = "Orin desktops preserve the login home and expose Flatpak launchers";
      ok =
        lib.all
          (
            host:
            let
              gui = host.microvm.vms.gui-vm.evaluatedConfig.config;
            in
            lib.any (
              directory: (directory.directory or null) == "/home/${gui.ghaf.users.admin.name}"
            ) gui.ghaf.storagevm.directories
            && lib.elem "/Shares/Unsafe flatpak-vm share/.flatpak-share" gui.environment.profiles
            && gui.ghaf.services.power-manager.enable
            && gui.systemd.services.gui-shutdown-interceptor.serviceConfig.RemainAfterExit
            && lib.elem "givc-gui-vm.service" gui.systemd.services.gui-shutdown-interceptor.after
            &&
              gui.systemd.services.ghaf-crosvm-poweroff.serviceConfig.RuntimeDirectory == "ghaf-crosvm-poweroff"
          )
          [
            agx
            (hostConfig baseTargets.nvidia-jetson-orin-nx-debug)
            (hostConfig baseTargets.nvidia-jetson-orin-nx-verity-luks-debug)
          ];
    }
    {
      name = "split NX retains the VFIO memory budgets";
      ok =
        splitNx.microvm.vms.gpu-vm.evaluatedConfig.config.microvm.mem == 2048
        && splitNx.microvm.vms.disp-vm.evaluatedConfig.config.microvm.mem == 1536;
    }
    {
      name = "Ghaf owns the split display workload and DCE shutdown ordering";
      ok =
        let
          display = splitAgx.microvm.vms.disp-vm.evaluatedConfig.config;
        in
        display.systemd.services ? kms-owner
        && lib.elem "kms-owner.service" display.systemd.services.dce-rm-deinit.before;
    }
    {
      name = "combined GUI guests order DCE shutdown after the compositor";
      ok =
        let
          gui = agx.microvm.vms.gui-vm.evaluatedConfig.config;
        in
        !(gui.systemd.services ? kms-owner)
        && lib.elem "greetd.service" gui.systemd.services.dce-rm-deinit.before;
    }
    {
      name = "split GPU and display VMs inherit organization SSH keys once";
      ok =
        lib.all
          (
            name:
            splitAgx.microvm.vms.${name}.evaluatedConfig.config.ghaf.security.ssh.release.trustedUserCAKeys
            == [ "ssh-ed25519 AAAATESTKEY orin-crosvm-test" ]
          )
          [
            "gpu-vm"
            "disp-vm"
          ];
    }
    {
      name = "all expected Orin configurations are exported";
      ok = builtins.length (builtins.attrNames orinTargets) == 112;
    }
    {
      name = "AGX NetVM waits for MGBE bind and Crosvm overlay preparation";
      ok = lib.all (unit: lib.elem unit agxNetService.requires) [
        "bindMgbe0.service"
        "prepareMgbe0CrosvmOverlay.service"
        "bindMttcan.service"
        "ghaf-device-manager.service"
      ];
    }
    {
      name = "AGX NetVM consumes the Jetpack-owned MGBE and MTTCAN overlays";
      ok =
        lib.elem "/run/mgbe0-net-vm.dtbo" agxNetVm.microvm.crosvm.deviceTreeOverlays
        && lib.any (
          overlay: lib.hasInfix "mttcan-crosvm-overlay.dtbo" (toString overlay)
        ) agxNetVm.microvm.crosvm.deviceTreeOverlays;
    }
    {
      name = "NX NetVM waits for MTTCAN binding and owns both controllers";
      ok =
        lib.elem "bindMttcan.service" nxNetService.requires
        && lib.length nxMttcanDevices == 2
        && lib.any (
          device: device.path == "c310000.mttcan" && device.crosvm.dtSymbol == "mttcan0"
        ) nxMttcanDevices
        && lib.any (
          device: device.path == "c320000.mttcan" && device.crosvm.dtSymbol == "mttcan1"
        ) nxMttcanDevices
        && lib.all (module: lib.elem module nxNetVm.boot.kernelModules) [
          "nvpps"
          "mttcan"
        ]
        && lib.length nxMttcanModulePackages == 1;
    }
    {
      name = "NX NetVM BPMP policy contains both MTTCAN controllers";
      ok =
        lib.all (id: lib.elem id nx.hardware.nvidia-jetpack.virtualization.bpmpHost.consumers.net-vm.clocks)
          [
            9
            10
            11
            12
            94
            284
            285
          ]
        &&
          lib.all (id: lib.elem id nx.hardware.nvidia-jetpack.virtualization.bpmpHost.consumers.net-vm.resets)
            [
              4
              5
            ];
    }
    {
      name = "AGX NetVM consumes host hardware information over virtiofs";
      ok = agxNetVm.ghaf.services.hwinfo-guest.filePath == "/run/ghaf-hwinfo/hwinfo.json";
    }
    {
      name = "Crosvm guests stop before the GIVC coordinator's shutdown helper";
      ok =
        lib.all
          (
            host:
            let
              shutdownUnits = lib.filterAttrs (
                name: _: lib.hasPrefix "ghaf-crosvm-shutdown-" name
              ) host.systemd.services;
              coordinator = "ghaf-crosvm-shutdown-admin-vm";
            in
            shutdownUnits ? ${coordinator}
            && lib.all (
              name:
              if name == coordinator then
                !lib.any (unit: lib.hasPrefix "ghaf-crosvm-shutdown-" unit) shutdownUnits.${name}.after
              else
                lib.elem "${coordinator}.service" shutdownUnits.${name}.after
            ) (lib.attrNames shutdownUnits)
          )
          [
            agx
            (hostConfig baseTargets.nvidia-jetson-orin-nx-debug)
            splitAgx
          ];
    }
    {
      name = "MGBE0 timeouts retain the DMA owner instead of force-stopping it";
      ok =
        agxNetService.serviceConfig.KillMode == "none"
        && agxNetService.unitConfig.SurviveFinalKillSignal
        && lib.any (
          command: lib.hasInfix "guard-crosvm-net-vm-start" command
        ) agxNetService.serviceConfig.ExecStartPre;
    }
    {
      name = "Crosvm shutdown is bounded and reuses the MicroVM helper";
      ok =
        nxGuiShutdown.serviceConfig.TimeoutStopSec == "95"
        && agx.systemd.services."microvm@admin-vm".serviceConfig.TimeoutStopSec == "95"
        && nxGuiShutdown.serviceConfig.WorkingDirectory == "/var/lib/microvms/gui-vm";
    }
    {
      name = "Ghaf composes the split GPU and display VM target";
      ok =
        !splitAgx.ghaf.virtualization.microvm.guivm.enable
        && splitAgx.ghaf.virtualization.microvm.gpuvm.enable
        && splitAgx.ghaf.virtualization.microvm.dispvm.enable
        &&
          splitAgx.hardware.nvidia-jetpack.virtualization.gpuPassthroughHost.assignments == {
            gpu-vm.role = "compute";
            disp-vm.role = "display";
          }
        && splitAgx.microvm.vms ? "gpu-vm"
        && splitAgx.microvm.vms ? "disp-vm"
        && lib.all (vm: vm.microvm.hypervisor == "crosvm") splitVmConfigs;
    }
    {
      name = "explicit QEMU overrides retain the supported rollback path";
      ok =
        qemuFallback.ghaf.hardware.passthrough.deviceManager.backend == "vhotplug"
        && !qemuFallback.hardware.nvidia-jetpack.virtualization.mttcanHost.enable
        && lib.all (vm: vm.microvm.hypervisor == "qemu") (vmConfigs qemuFallback)
        && qemuFallback.systemd.services ? vhotplug
        && !(qemuFallback.systemd.services ? ghaf-device-manager)
        && !qemuFallback.microvm.vms.gui-vm.evaluatedConfig.config.ghaf.services.power-manager.enable
        && !(
          qemuFallback.microvm.vms.gui-vm.evaluatedConfig.config.systemd.services ? gui-shutdown-interceptor
        )
        && !(qemuFallback.microvm.vms.gui-vm.evaluatedConfig.config.systemd.services ? ghaf-crosvm-poweroff)
        && !(qemuFallback.systemd.services ? ghaf-crosvm-shutdown-admin-vm);
    }
  ];

  failed = map (assertion: assertion.name) (lib.filter (assertion: !assertion.ok) assertions);
in
# Keep target evaluation lazy when flake show inspects the check's name.
runCommand "orin-crosvm-targets" { } (
  assert lib.assertMsg (
    failed == [ ]
  ) "Orin Crosvm target policy: ${lib.concatStringsSep "; " failed}";
  ''
    grep -Fq 'while ((SECONDS < grace_deadline))' ${nxGuiShutdownScript}
    grep -Fq /booted/bin/microvm-shutdown ${nxGuiShutdownScript}
    touch "$out"
  ''
)
