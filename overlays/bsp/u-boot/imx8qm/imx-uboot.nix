{ pkgs }:

with pkgs; let

  inherit buildUBoot;
  inherit (callPackage ./imx-atf.nix { inherit buildArmTrustedFirmware; }) armTrustedFirmwareiMX8QM;
  imx-firmware = callPackage ./imx-firmware.nix { inherit pkgs; };
  imx-mkimage = buildPackages.callPackage ./imx-mkimage.nix { inherit pkgs; };

in {

  ubootImx8 = buildUBoot {
    version = "2022.04";
    src = fetchgit {
      url = "https://source.codeaurora.org/external/imx/uboot-imx.git";
      # tag: "lf_v2022.04"
      rev = "1c881f4da83cc05bee50f352fa183263d7e2622b";
      sha256 = "sha256-0TS6VH6wq6PwZUq6ekbuLaisZ9LrE0/haU9nseGdiE0=";
    };
    BL31 = "${armTrustedFirmwareiMX8QM}/bl31.bin";
    patches = [ ./patches/0001-Add-UEFI-boot-on-imx8qm_mek.patch ];
    enableParallelBuilding = true;
    defconfig = "imx8qm_mek_defconfig";
    extraMeta.platforms = ["aarch64-linux"];
    preBuildPhases = [ "copyBinaries" ];
    copyBinaries = ''
      install -m 0644 ${imx-firmware}/mx8qmb0-ahab-container.img ./ahab-container.img
      install -m 0644 ${imx-firmware}/mx8qm-mek-scfw-tcm.bin ./mx8qm-mek-scfw-tcm.bin
      install -m 0644 $BL31 ./u-boot-atf.bin
    '';
    postBuild = ''
      ${imx-mkimage} -commit > head.hash
      cat u-boot.bin head.hash > u-boot-hash.bin
      dd if=u-boot-hash.bin of=u-boot-atf.bin bs=1K seek=128
      ${imx-mkimage} -soc QM -rev B0 -append ahab-container.img -c -scfw mx8qm-mek-scfw-tcm.bin -ap u-boot-atf.bin a35 0x80000000 -out flash.bin
    '';
    filesToInstall = [ "flash.bin" ];
  };

  inherit imx-firmware;
}

