# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# The laptop machine table.
#
# Intel laptops share the generic `intel-laptop` image: display, network and audio
# are passed through by PCI class rather than per-device ID, input by udev property,
# and per-board quirks (ACS ids, suspend mode, webcam and fingerprint VID:PIDs) live
# in union lists that one image carries for the whole fleet. A new Intel laptop needs
# no entry here at all -- at most a quirk added to one of those lists.
#
# The remaining entries are boards the generic image cannot describe: AMD IOMMU,
# desktops, and discrete GPUs whose audio function must be paired with the display
# device by hand rather than swept up by class matching.
#
# HARD RULE: data only. No `ghaf.*`, no `lib` calls, no conditionals, no inline
# modules. Anything a machine needs beyond the fields below belongs in
# modules/reference/hardware/. Enforced by checks.laptop-table-is-data.
#
# Fields:
#   hardware   suffix of nixosModules.hardware-*        (required)
#   variants   subset of [ "debug" "release" ]          (required)
#   product    reference profile to enable              (default "mvp-user-trial")
#   axes       names from ./axes.nix, expanded into one (default [ ])
#              target per subset; axes sharing a group
#              are mutually exclusive
#   sysupdate  also emit an A/B update image for the    (default false)
#              axis-free target
{
  # keep-sorted start block=yes newline_separated=yes
  # Intel + NVIDIA. Suspend does not resume on this board, the panel backlight is
  # owned by the host, and the NIC needs an out-of-tree driver in net-vm.
  alienware-m18-R2 = {
    hardware = "alienware-m18-r2";
    variants = [
      "debug"
      "release"
    ];
  };

  # AMD desktop, discrete Quadro passed through as a four-function group.
  demo-tower-mk1 = {
    hardware = "demo-tower-mk1";
    variants = [
      "debug"
      "release"
    ];
  };

  # The generic image. Covers every Intel laptop in the fleet.
  intel-laptop = {
    hardware = "intel-laptop";
    variants = [
      "debug"
      "release"
    ];
    axes = [
      "low-mem"
      "minimal-mem"
      "storeDisk"
    ];
    sysupdate = true;
  };

  # Same image, different application set.
  intel-laptop-extras = {
    hardware = "intel-laptop";
    product = "mvp-user-trial-extras";
    variants = [
      "debug"
      "release"
    ];
  };

  # AMD laptop: amd_iommu, amdgpu, AMD ACP audio, and a simpledrm renderer because
  # iGPU passthrough does not work on this board.
  lenovo-t14-amd-gen5 = {
    hardware = "lenovo-t14-amd-gen5";
    variants = [
      "debug"
      "release"
    ];
  };

  # Intel desktop, discrete RTX 5080 with the open NVIDIA drivers.
  tower-5080 = {
    hardware = "tower-5080";
    variants = [
      "debug"
      "release"
    ];
  };
  # keep-sorted end
}
