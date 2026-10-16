# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
(_final: prev: {
  # Fix CUDA assertion failures for x86_64 cross-compile build
  config =
    prev.config
    // prev.lib.optionalAttrs (prev.stdenv.hostPlatform.system != "aarch64-linux") {
      cudaCapabilities = [ ];
    };

  nvidia-jetpack = prev.nvidia-jetpack.overrideScope (
    _sfinal: sprev: {
      kernelPackagesOverlay =
        kfinal: kprev:
        let
          base = sprev.kernelPackagesOverlay kfinal kprev;
          inherit (kfinal) kernel;
        in
        base
        // prev.lib.optionalAttrs (base ? nvidia-oot-modules) {
          nvidia-oot-modules = base.nvidia-oot-modules.overrideAttrs (oldAttrs: {
            # The output path that `buildLinux` adds to kernel.makeFlags ("O=$(buildRoot)") is
            # incorrect for OOT builds. Let's use commonMakeFlags instead.
            # It also gets rid of "--eval=undefine modules" that breaks hwpm build.
            makeFlags =
              kernel.commonMakeFlags
              ++ prev.lib.subtractLists (kernel.makeFlags ++ [ "kernel_name=noble" ]) oldAttrs.makeFlags
              ++ [
                "NV_OOT_REALTEK_RTL8822CE_SKIP_BUILD=y"
                "NV_OOT_REALTEK_RTL8852CE_SKIP_BUILD=y"
              ];

            postPatch = (oldAttrs.postPatch or "") + ''
              if ! grep -q rtk_set_quirk nvidia-oot/drivers/bluetooth/realtek/rtk_bt.h; then
                patch -p1 -d nvidia-oot < ${./0002-rtk_btusb-Fix-for-kernel-6.16.patch}
              fi
            '';
          });
        };
    }
  );
})
