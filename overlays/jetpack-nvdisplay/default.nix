# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Build fix for jetpack-nixos' L4T OOT modules.
#
# nvdisplay's and unifiedgpudisp's Kbuild run kernel-open/pahole.sh as PAHOLE
# for the module BTF step, but jetpack-nixos assembles l4t-oot-sources with
# `cp --no-preserve=all`, which drops the scripts' exec bit, so modfinal fails
# with "pahole.sh: Permission denied" (Error 126).
(_final: prev: {
  nvidia-jetpack = prev.nvidia-jetpack.overrideScope (
    _jfinal: jprev: {
      kernelPackagesOverlay =
        kfinal: kprev:
        let
          base = jprev.kernelPackagesOverlay kfinal kprev;
        in
        base
        # Only the L4T >= 36 branch of kernelPackagesOverlay defines nvidia-oot-modules.
        // prev.lib.optionalAttrs (base ? nvidia-oot-modules) {
          nvidia-oot-modules = base.nvidia-oot-modules.overrideAttrs (o: {
            postPatch = (o.postPatch or "") + ''
              chmod +x {nvdisplay,unifiedgpudisp}/kernel-open/pahole.sh
            '';
          });
        };
    }
  );
})
