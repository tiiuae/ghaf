# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Display-only peer for the compute gpu-vm.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.passthroughs.disp_vm;
  configuredDispVmVmm = config.ghaf.virtualization.vmConfig.sysvms.dispvm.vmm or null;
  dispVmVmm =
    if configuredDispVmVmm != null then
      configuredDispVmVmm
    else
      config.ghaf.virtualization.vmConfig.defaultSysVmVmm;
  isCrosvm = dispVmVmm == "crosvm";
  virt = config.ghaf.hardware.nvidia.virtualization;

  # Guest RAM and display keyholes use fixed GPA-to-HPA mappings.
  reservedMem = [
    {
      dev = "b0000000.scanout_p";
      base = "0xb0000000";
    }
    {
      dev = "b8000000.dispram_lo_p";
      base = "0xb8000000";
    }
    {
      dev = "200000000.dispram_hi_p";
      base = "0x200000000";
    }
  ];
  dispCaps = [
    {
      dev = "13830000.disp_caps_pt";
      base = "0x66230000";
    }
    {
      dev = "13870000.disp_chan_pt";
      base = "0x66270000";
    }
    {
      dev = "138c8000.disp_cursor_pt";
      base = "0x662c8000";
    }
  ];
  mappings = reservedMem ++ dispCaps;
  allDevs = map (r: r.dev) mappings;
  vfioArgs = lib.concatMap (r: [
    "-device"
    "vfio-platform,host=${r.dev},mmio-base=${r.base}"
  ]) mappings;

  inherit (import ../payload { inherit lib pkgs; })
    capabilities
    mkPayload
    boardFor
    ;
  cap = capabilities.dispvm;
  payload = mkPayload cap;
  board = boardFor config.ghaf.hardware.nvidia.orin.somType;
  _capOk =
    payload.needsDceBridge
    && payload.noSyncpointPatch
    && payload.expDtDefines == "-DEXP_DROP_HOST1X -DEXP_DROP_GPU ";
  mkOrinGpuGuestModule = import ../payload/guest-module.nix;
  mkOrinGpuCrosvmOverlay = import ../payload/crosvm-overlay.nix;

  dispvm-dtb = pkgs.stdenv.mkDerivation {
    name = "dispvm-dtb";
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./tegra234-dispvm.dts
        ./tegra234-dispvm-memory.dtsi
      ];
    };
    nativeBuildInputs = [
      pkgs.buildPackages.dtc
      pkgs.buildPackages.gcc
    ];
    buildPhase =
      let
        kernel = config.boot.kernelPackages.kernel;
        mainInc = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/include";
        gpuvmDtsi = lib.fileset.toSource {
          root = ../gpu-vm;
          fileset = lib.fileset.unions [
            ../gpu-vm/tegra234-gpuvm-base.dtsi
            ../gpu-vm/tegra234-gpuvm-proxies.dtsi
            ../gpu-vm/tegra234-gpuvm-display.dtsi
            ../gpu-vm/tegra234-gpuvm-dummies.dtsi
            ../gpu-vm/generated
          ];
        };
      in
      ''
        $CC -E -nostdinc -undef -D__DTS__ -DEXP_DROP_HOST1X -DEXP_DROP_GPU -DGHAF_DCB_DTSI='"${board.dcbDtsi}"' -x assembler-with-cpp \
          -I${mainInc} \
          -I${../gpu-vm/nv-dt-bindings} \
          -I${gpuvmDtsi} \
          -I. \
          tegra234-dispvm.dts > preprocessed.dts
        dtc -I dts -O dtb -o tegra234-dispvm.dtb preprocessed.dts
      '';
    installPhase = ''
      mkdir -p $out
      cp tegra234-dispvm.dtb $out/
    '';
  };
  dispvm-crosvm-overlay = mkOrinGpuCrosvmOverlay {
    inherit
      lib
      pkgs
      board
      cap
      ;
    kernel = config.boot.kernelPackages.kernel;
    dtsDir = ../gpu-vm;
    overlayDts = ./tegra234-dispvm-crosvm-overlay.dts;
  };
in
{
  _file = ./default.nix;

  options.ghaf.hardware.nvidia.passthroughs.disp_vm.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Pass the Tegra234 display path through to disp-vm on NVIDIA Orin AGX";
  };

  config =
    assert lib.assertMsg _capOk
      "disp-vm: capabilities.dispvm payload drifted (expects DCE bridge + no-syncpoint NVKMS + '-DEXP_DROP_HOST1X -DEXP_DROP_GPU')";
    lib.mkIf cfg.enable {
      ghaf.virtualization.microvm.dispvm.enable = true;

      systemd.services.bindDispVm = {
        description = "Bind disp-vm display devices to vfio-platform";
        wantedBy = [ "multi-user.target" ];
        before = [ "microvm@disp-vm.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = "yes";
          ExecStartPre = map (
            d:
            "${pkgs.bash}/bin/bash -c \"echo vfio-platform > /sys/bus/platform/devices/${d}/driver_override\""
          ) allDevs;
          ExecStart = map (
            d:
            "${pkgs.bash}/bin/bash -c '"
            + "cur=$(basename \"$(readlink -f /sys/bus/platform/devices/${d}/driver 2>/dev/null)\"); "
            + "if [ \"$cur\" != vfio-platform ]; then echo ${d} > /sys/bus/platform/drivers/vfio-platform/bind; fi'"
          ) allDevs;
        };
      };
      systemd.services."microvm@disp-vm" = {
        requires = [ "bindDispVm.service" ];
        after = [ "bindDispVm.service" ];
        environment = lib.mkIf (!isCrosvm) { GHAF_DCE_GUEST = "1"; };
        serviceConfig.ExecStartPre = lib.optionals isCrosvm [
          "${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/test -r /dev/bpmp-host && ${pkgs.coreutils}/bin/test -w /dev/bpmp-host'"
          "${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/test -r /dev/dce-host && ${pkgs.coreutils}/bin/test -w /dev/dce-host'"
        ];
      };

      ghaf.hardware.definition.dispvm.extraModules = [
        (mkOrinGpuGuestModule {
          inherit lib cap vfioArgs;
          dtb = dispvm-dtb;
          dtbName = "tegra234-dispvm.dtb";
          crosvmOverlay = dispvm-crosvm-overlay;
          inherit (virt) sourcesPatch;
        })
      ];
    };
}
