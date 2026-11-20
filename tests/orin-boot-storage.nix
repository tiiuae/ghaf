# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs }:
let
  luksUuid = "0ada0e5b-0e5b-4e5b-8e5b-0000000000a9";
  selector = import ../modules/reference/hardware/jetpack/nvidia-jetson-orin/select-boot-storage.nix {
    inherit pkgs luksUuid;
  };
  writer = import ../modules/reference/hardware/jetpack/nvidia-jetson-orin/write-verity-nvme.nix {
    inherit pkgs;
  };
  storage =
    (pkgs.lib.evalModules {
      specialArgs = { inherit pkgs; };
      modules = [
        ../modules/reference/hardware/jetpack/nvidia-jetson-orin/verity-boot-storage.nix
        ({ lib, ... }: {
          options = lib.genAttrs [ "ghaf" "boot" "fileSystems" ] (
            _: lib.mkOption { type = lib.types.attrs; }
          );
          config.ghaf = {
            partitioning.verity.enable = true;
            hardware.nvidia.orin.diskEncryption = {
              enable = true;
              mapperName = "cryptroot";
              inherit luksUuid;
            };
          };
        })
      ];
    }).config.boot.initrd.systemd;
  checkTools = pkgs.writeShellScript "check-boot-storage-tools" ''
    test -x ${pkgs.lib.getExe selector}
    ${pkgs.bash}/bin/bash -n ${pkgs.lib.getExe selector}
    echo BOOT_STORAGE_TOOLS_PRESENT
  '';
in
pkgs.testers.nixosTest {
  name = "orin-boot-storage";
  nodes.machine = {
    virtualisation.useEFIBoot = true;
    virtualisation.useBootLoader = true;
    boot.loader.systemd-boot.enable = true;
    boot.kernelModules = [ "efivarfs" ];
    boot.initrd = {
      kernelModules = [ "efivarfs" ];
      systemd = {
        storePaths = storage.storePaths ++ [ checkTools ];
        services = {
          ghaf-select-boot-storage = storage.services.ghaf-select-boot-storage // {
            serviceConfig = storage.services.ghaf-select-boot-storage.serviceConfig // {
              ExecStart = checkTools;
            };
          };
          pre-disk-unique-key = storage.services.pre-disk-unique-key // {
            unitConfig = storage.services.pre-disk-unique-key.unitConfig // {
              DefaultDependencies = false;
            };
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${pkgs.coreutils}/bin/true";
            };
          };
          "systemd-cryptsetup@cryptroot" = {
            inherit (storage.services."systemd-cryptsetup@cryptroot") requires after;
            wantedBy = [ "initrd.target" ];
            unitConfig = {
              DefaultDependencies = false;
              IgnoreOnIsolate = true;
            };
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${pkgs.coreutils}/bin/true";
              ExecStop = "${pkgs.coreutils}/bin/false";
            };
          };
        };
      };
    };
    systemd.mounts = storage.mounts or [ ];
    systemd.services.ghaf-select-boot-storage = storage.services.ghaf-select-boot-storage // {
      wantedBy = [ ];
      serviceConfig = storage.services.ghaf-select-boot-storage.serviceConfig // {
        ExecStart = "${pkgs.lib.getExe selector} /tmp/efi";
      };
    };
    virtualisation.emptyDiskImages = [
      128
      128
    ];
    environment.systemPackages = with pkgs; [
      selector
      writer
      gptfdisk
      cryptsetup
      dosfstools
      glibc.bin
    ];
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("journalctl -b -u ghaf-select-boot-storage --no-pager | grep BOOT_STORAGE_TOOLS_PRESENT")
    machine.fail("systemctl is-failed systemd-cryptsetup@cryptroot")
    machine.fail("journalctl -b -u systemd-cryptsetup@cryptroot --no-pager | grep -E 'Failed|Control process exited'")
    machine.succeed("truncate -s 4M /tmp/esp && mkfs.vfat -n ESP /tmp/esp && truncate -s 32M /tmp/app && printf key >/tmp/key")
    machine.succeed("cryptsetup luksFormat --batch-mode --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --uuid ${luksUuid} --key-file /tmp/key /tmp/app")
    machine.succeed("write-verity-nvme /dev/vdb /tmp/esp /tmp/app && write-verity-nvme /dev/vdc /tmp/esp /tmp/app && udevadm settle")
    def identify(partition):
        machine.succeed(f"head -c 4 /dev/zero >/tmp/efi && blkid -s PARTUUID -o value {partition} | tr -d '\\n' | iconv -f UTF-8 -t UTF-16LE >>/tmp/efi")
    with subtest("select the boot disk despite duplicate LUKS UUID and ESP label"):
        for disk in ["vdc", "vdb"]:
            identify(f"/dev/{disk}1")
            machine.succeed("systemctl restart ghaf-select-boot-storage")
            machine.succeed(f"test $(readlink -f /dev/disk/ghaf-root) = /dev/{disk}2 && test $(readlink -f /dev/disk/ghaf-esp) = /dev/{disk}1")
            machine.succeed("systemctl is-active --quiet $(systemd-escape --path --suffix=device /dev/disk/ghaf-root) && systemctl is-active --quiet $(systemd-escape --path --suffix=device /dev/disk/ghaf-esp)")
            machine.succeed("cryptsetup open --key-file /tmp/key /dev/disk/ghaf-root selected && cryptsetup close selected")
        machine.succeed("systemctl restart systemd-udevd && udevadm trigger --subsystem-match=block && udevadm settle")
        machine.succeed("test $(readlink -f /dev/disk/ghaf-root) = /dev/vdb2 && test $(readlink -f /dev/disk/ghaf-esp) = /dev/vdb1")
    with subtest("mount EFI variables when the API filesystem is not mounted yet"):
        machine.succeed("umount /sys/firmware/efi/efivars && systemctl restart ghaf-select-boot-storage && mountpoint -q /sys/firmware/efi/efivars")
    before = machine.succeed("sha256sum /dev/vdb /dev/vdc")
    with subtest("reject missing or malformed boot identity without changing disks"):
        machine.fail("select-boot-storage /tmp/missing")
        machine.succeed("printf malformed >/tmp/invalid")
        machine.fail("select-boot-storage /tmp/invalid")
        assert before == machine.succeed("sha256sum /dev/vdb /dev/vdc")
    with subtest("reject a cloned ESP GUID"):
        machine.succeed("sgdisk -u 1:$(blkid -s PARTUUID -o value /dev/vdb1) /dev/vdc && udevadm settle")
        machine.fail("select-boot-storage /tmp/efi")
    with subtest("never unlock the other disk when the boot disk has no matching APP"):
        machine.succeed("sgdisk -u 1:R /dev/vdc && cryptsetup luksUUID --batch-mode --uuid 11111111-1111-1111-1111-111111111111 /dev/vdb2 && udevadm settle")
        machine.fail("select-boot-storage /tmp/efi")
  '';
}
