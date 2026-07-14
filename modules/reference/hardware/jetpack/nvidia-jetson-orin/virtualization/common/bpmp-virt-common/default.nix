# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.virtualization;
  kernelVersion = config.boot.kernelPackages.kernel.version;

  # The bpmp-virt proxy drivers are carried as ordinary source files under
  # ./sources, not buried in a diff, so they can be read, grepped and reviewed as
  # code. Only the four in-tree hooks they need (drivers/firmware/tegra/Kconfig,
  # Makefile, bpmp.c, bpmp-tegra186.c) remain a hand-maintained patch.
  bpmpVirtSources = pkgs.runCommand "bpmp-virt-sources" { } (
    ''
      cp -r ${./sources} $out
      chmod -R u+w $out
    ''
    + lib.optionalString cfg.bpmpAllowAllDomains ''
      substituteInPlace $out/drivers/firmware/tegra/bpmp-host-proxy/bpmp-host-proxy.c \
        --replace-fail '#define BPMP_HOST_ALLOWS_ALL   0' '#define BPMP_HOST_ALLOWS_ALL   1'
    ''
  );

  # boot.kernelPatches only takes patches, so synthesise the add-files diff from
  # the sources above rather than keeping ~1100 lines of `+` in the tree.
  # Timestamps are pinned to the epoch: diff prints them into the ---/+++ headers,
  # and a build-time mtime would rehash this patch, and the kernel, on every build.
  bpmpVirtSourcesPatch = pkgs.runCommand "bpmp-virt-add-sources.patch" { } ''
    mkdir -p a
    cp -r ${bpmpVirtSources} b
    chmod -R u+w b
    find a b -exec touch -h -d @0 {} +
    diff -Naur a b > "$out" || true
    test -s "$out"
  '';
in
{
  _file = ./default.nix;

  options.ghaf.hardware.nvidia.virtualization = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable virtualization support for NVIDIA Orin

        This option is an implementation level detail and is toggled automatically
        by modules that need it. Manually enabling this option is not recommended in
        release builds.
      '';
    };

    sourcesPatch = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      default = bpmpVirtSourcesPatch;
      defaultText = lib.literalExpression "<generated add-files patch>";
      description = ''
        Generated patch that adds the bpmp-virt proxy drivers to a kernel tree.

        Exposed so a guest VM's kernel can be given the same drivers: the host
        needs the host proxy, the guest needs the guest proxy, and both live in
        the same source directory.
      '';
    };

    bpmpAllowAllDomains = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Let the BPMP host proxy service every clock, reset and power domain a
        guest asks for, instead of consulting the `allowed-clocks` /
        `allowed-resets` properties on the `bpmp_host_proxy` device-tree node.

        DANGEROUS. A guest kernel's clk_disable_unused() / genpd_power_off_unused()
        run BPMP requests to turn off every clock and power domain the guest does
        not claim. With no allow-list those reach the real BPMP and can switch off
        hardware the HOST is using -- e.g. its eMMC controller, which wedges the
        host. The guest must ALSO boot with `clk_ignore_unused pd_ignore_unused`;
        the passthrough modules add those. Default off. Only ever set true briefly,
        on a guest carrying those kernel params, to discover what the guest
        actually requests so the allow-list can be written.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.versionAtLeast kernelVersion "6.6";
        message = ''
          ghaf.hardware.nvidia.virtualization needs kernel >= 6.6; got ${kernelVersion}.
          The bpmp-virt drivers under bpmp-virt-common/sources/ are written against the
          6.6 drivers/firmware/tegra layout. Set
          ghaf.hardware.nvidia.orin.kernelVersion = "upstream-6-6".
        '';
      }
    ];

    boot.kernelPatches = [
      {
        name = "Added Configurations to Support Vda";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
          PCI_STUB = lib.mkDefault yes;
          VFIO = lib.mkDefault yes;
          VIRTIO_PCI = lib.mkDefault yes;
          VIRTIO_MMIO = lib.mkDefault yes;
          HOTPLUG_PCI = lib.mkDefault yes;
          PCI_DEBUG = lib.mkDefault yes;
          PCI_HOST_GENERIC = lib.mkDefault yes;
          VFIO_IOMMU_TYPE1 = lib.mkDefault yes;
          HOTPLUG_PCI_ACPI = lib.mkDefault yes;
          PCI_HOST_COMMON = lib.mkDefault yes;
          VFIO_PLATFORM = lib.mkDefault yes;
          TEGRA_BPMP_GUEST_PROXY = lib.mkDefault no;
          TEGRA_BPMP_HOST_PROXY = lib.mkDefault no;
        };
      }
      {
        name = "Vfio_platform Reset Required False";
        patch = ./patches/0002-vfio_platform-reset-required-false.patch;
      }
      {
        name = "bpmp-virt proxy drivers";
        patch = cfg.sourcesPatch;
      }
      {
        name = "bpmp-virt core hooks";
        patch = ./patches/0001-bpmp-virt-hooks.patch;
      }
    ];

    boot.kernelParams = [
      # The passed-through platform device raises level-triggered IRQs the host
      # GIC can't remap 1:1 to the guest; allow VFIO to forward them anyway.
      "vfio_iommu_type1.allow_unsafe_interrupts=1"
      # Let SMMU stream IDs without a matching context fall through to bypass so
      # the guest-driven MGBE0 DMAs before its SMMU context is programmed.
      "arm-smmu.disable_bypass=0"
    ];
  };
}
