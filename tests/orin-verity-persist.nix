# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs }:
let
  resize = import ../modules/reference/hardware/jetpack/nvidia-jetson-orin/resize-verity-luks.nix {
    inherit pkgs;
    mapperName = "cryptroot";
    keyDescription = "test-key";
  };
  node = encrypted: { lib, ... }: {
    imports = [ ../modules/partitioning/firstboot-persist.nix ];
    options.ghaf = lib.mkOption { type = lib.types.attrs; };
    config = {
      ghaf = {
        partitioning.verity = {
          enable = true;
          rootSlotSizeMiB = if encrypted then 64 else null;
          veritySlotSizeMiB = if encrypted then 16 else null;
        };
        hardware.nvidia.orin.diskEncryption.enable = encrypted;
      };
      systemd.services.firstboot-persist.wantedBy = lib.mkForce [ ];
      fileSystems."/persist".options = [ "noauto" ];
      swapDevices = lib.mkForce [ ];
      virtualisation.emptyDiskImages = [
        8192
        512
      ];
      environment.systemPackages = with pkgs; [
        resize
        keyutils
        lvm2
        gptfdisk
        parted
        cryptsetup
      ];
    };
  };
in
pkgs.testers.nixosTest {
  name = "orin-verity-persist";
  nodes = {
    plain = node false;
    encrypted = node true;
  };
  testScript = ''
    start_all()
    for machine, is_encrypted in [(plain, False), (encrypted, True)]:
        machine.wait_for_unit("multi-user.target")
        if is_encrypted:
            # Model a small flashed image whose backup GPT has not yet moved.
            machine.succeed("truncate -s 512M /tmp/layout.raw && sgdisk --move-main-table=8 -n 1:2048:+256M -t 1:8e00 /tmp/layout.raw && dd if=/tmp/layout.raw of=/dev/vdb bs=1M conv=sparse,fsync status=none && partprobe /dev/vdb && udevadm settle")
        else:
            machine.succeed("sgdisk --move-main-table=8 -n 1:2048:+256M -t 1:8e00 /dev/vdb && udevadm settle")
        pv = "/dev/vdb1"
        if is_encrypted:
            machine.succeed("printf test-key >/run/key && cryptsetup luksFormat --batch-mode --sector-size 4096 --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --key-file /run/key /dev/vdb1 && cryptsetup open --key-file /run/key /dev/vdb1 cryptroot")
            # A second LUKS partition has the same UUID, but is not the opened mapping.
            machine.succeed("sgdisk -n 1:2048:0 -t 1:8309 /dev/vdc && udevadm settle")
            machine.succeed("cryptsetup luksFormat --batch-mode --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --key-file /run/key --uuid $(cryptsetup luksUUID /dev/vdb1) /dev/vdc1")
            foreign = machine.succeed("sha256sum /dev/vdc")
            machine.succeed("keyctl link @u @s && keyctl padd user test-key @u </run/key && resize-verity-luks")
            assert foreign == machine.succeed("sha256sum /dev/vdc")
            machine.succeed("test $(blockdev --getsize64 /dev/mapper/cryptroot) -gt 8000000000")
            machine.succeed("sync")
            written = machine.succeed("awk '{print $7}' /sys/class/block/vdb/stat")
            machine.succeed("resize-verity-luks && sync")
            assert written == machine.succeed("awk '{print $7}' /sys/class/block/vdb/stat"), "repeat resize wrote to disk"
            pv = "/dev/mapper/cryptroot"
        machine.succeed(f"pvcreate {pv} && vgcreate pool {pv} && lvcreate -L 64M -n root_original pool && lvcreate -L 16M -n verity_original pool")
        if is_encrypted:
            machine.succeed("lvcreate -L 64M -n root_empty pool && lvcreate -L 16M -n verity_empty pool")
        machine.succeed("systemctl start firstboot-persist && mkdir -p /persist && mount -t btrfs /dev/pool/persist /persist && echo retained >/persist/sentinel")
        machine.succeed("test $(blockdev --getsize64 /dev/vdb1) -gt 8000000000")
        if not is_encrypted:
            machine.succeed("vgs --noheadings --units m --nosuffix -o vg_free pool | awk '{exit !($1 >= 184)}'")
        original = machine.succeed("lvs --noheadings -o lv_name,lv_uuid pool && blkid -s UUID -o value /dev/pool/persist")
        machine.succeed("systemctl restart firstboot-persist && grep -qx retained /persist/sentinel")
        assert original == machine.succeed("lvs --noheadings -o lv_name,lv_uuid pool && blkid -s UUID -o value /dev/pool/persist")
        machine.succeed("umount /persist && wipefs --all /dev/pool/persist && dd if=/dev/pool/persist bs=1M count=1 status=none | sha256sum >/run/before")
        machine.fail("systemctl restart firstboot-persist")
        machine.succeed("dd if=/dev/pool/persist bs=1M count=1 status=none | sha256sum | cmp - /run/before")
  '';
}
