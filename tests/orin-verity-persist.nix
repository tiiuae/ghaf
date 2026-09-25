# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs }:
let
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
      virtualisation.emptyDiskImages = [ 8192 ];
      environment.systemPackages = with pkgs; [
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
        end = "0" if is_encrypted else "+256M"
        machine.succeed(f"sgdisk --move-main-table=8 -n 1:2048:{end} -t 1:8e00 /dev/vdb && udevadm settle")
        pv = "/dev/vdb1"
        if is_encrypted:
            machine.succeed("printf test-key >/run/key && cryptsetup luksFormat --batch-mode --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --key-file /run/key /dev/vdb1 && cryptsetup open --key-file /run/key /dev/vdb1 cryptroot")
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
