# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Build fix for jetpack-nixos' OOT modules against kernels >= 6.12.97.
#
# The Orin guest VMs (gpu-vm, disp-vm) build the L4T R36.5 OOT modules against
# vanilla `linuxPackages_6_12` rather than the jetpack kernel. 6.12.97 carries the
# backport of upstream commit 337b1b566db0 ("PCI: Fix restoring BARs on BAR resize
# rollback path"), which gave pci_resize_resource() a fourth `exclude_bars`
# argument. R36.5's nvdisplay still calls the three-argument form, so
# nvdisplay/kernel-open/nvidia/nv-pci.c fails to compile:
#
#   nv-pci.c:219:9: error: too few arguments to function 'pci_resize_resource';
#                   expected 4, have 3
#
# The patch adds the conftest NVIDIA carries upstream in open-gpu-kernel-modules
# (pci_resize_resource_has_exclude_bars_arg) and guards the call with it, so the
# same source builds against both the three- and four-argument kernels. The
# jetpack kernel itself still has the three-argument form, so the host build is
# unaffected -- the conftest simply doesn't match there.
#
# L4T < 38 only. From r38 onwards the patch fails to apply because nvdisplay
# already handles the four argument signature
#
# Scoped to the Jetson targets (applied by modules/reference/hardware/jetpack/
# default.nix) rather than living in overlays.default, the same way
# overlays.jetpack-python is. Drop this once tiiuae/jetpack-nixos carries the
# patch in pkgs/kernels/r36/patches/nvdisplay/.
(_final: prev: {
  nvidia-jetpack = prev.nvidia-jetpack.overrideScope (
    _jfinal: jprev:
    prev.lib.optionalAttrs (prev.lib.versionOlder jprev.l4tMajorMinorPatchVersion "38") {
      kernelPackagesOverlay =
        kfinal: kprev:
        let
          base = jprev.kernelPackagesOverlay kfinal kprev;
        in
        base
        # Only the L4T >= 36 branch of kernelPackagesOverlay defines
        # nvidia-oot-modules; on r35 it provides nvidia-display-driver instead.
        // prev.lib.optionalAttrs (base ? nvidia-oot-modules) {
          nvidia-oot-modules = base.nvidia-oot-modules.overrideAttrs (o: {
            # `src` is the combined l4t-oot-sources tree, so the nvdisplay project
            # lives under nvdisplay/ and the patch has to be applied scoped to it.
            postPatch = (o.postPatch or "") + ''
              patch -p1 -d nvdisplay < ${./0001-nvdisplay-conftest-pci_resize_resource-exclude_bars.patch}
            '';
          });
        };
    }
  );
})
