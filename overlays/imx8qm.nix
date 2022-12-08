
final: prev: {
  linux_imx8 = final.callPackage ./bsp/kernel/linux-imx8 { pkgs = final; };
  inherit ( final.callPackage ./bsp/u-boot/imx8qm/imx-uboot.nix { pkgs = final; }) ubootImx8 imx-firmware;

  spectrum-live = prev.spectrum-live.overrideAttrs (old: {
    KERNEL = final.linux_imx8;
    pname = "build/live.img";
    # The beginning of the first partition should be moved
    # because u-boot overwrites it (the size of u-boot is bigger
    # than the gap between GPT table and first partition (4Mb))
    # It was decided that 10Mb of space will be enough for u-boot,
    # so let's move all partitions by additional 6Mb to the right.
    installPhase = ''
      runHook preInstall
      dd if=/dev/zero bs=1M count=6 >> $pname
      partnum=$(sfdisk --json $pname | grep "node" | wc -l)
      while [ $partnum -gt 0 ]; do
        echo '+6M,' | sfdisk --move-data $pname -N $partnum
        partnum=$((partnum-1))
      done
      dd if=${final.ubootImx8}/flash.bin of=$pname bs=1k seek=32 conv=notrunc
      IMG=$pname
      ESP_OFFSET=$(sfdisk --json $IMG | jq -r '
        # Partition type GUID identifying EFI System Partitions
        def ESP_GUID: "C12A7328-F81F-11D2-BA4B-00A0C93EC93B";
        .partitiontable |
        .sectorsize * (.partitions[] | select(.type == ESP_GUID) | .start)
      ')
      mcopy -no -i $pname@@$ESP_OFFSET $KERNEL/dtbs/freescale/imx8qm-mek-hdmi.dtb ::/
      mcopy -no -i $pname@@$ESP_OFFSET ${final.imx-firmware}/hdmitxfw.bin ::/
      mv $pname $out
      runHook postInstall
    '';
  });
}
