# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Install from an HTTP image source and boot the result.
#
# The ISO path (tests/installer/default.nix) reads the image from a local
# directory. Netboot instead fetches it over HTTP at install time, which is the
# whole reason the netboot artefacts are target-independent and ~650 MB rather
# than ~7 GB. That fetch-and-write path is the risky part of the design, and
# this test covers it without needing PXE, firmware or a network boot:
#
#   * IMG_PATH is a URL, so resolve_image_source() takes the http branch
#   * the bmap is fetched -- and a missing bmap is fatal, never a silent dd
#   * curl | zstdcat | pv | bmaptool copy writes to a real disk
#   * bmaptool verifies per-range sha256 while copying, which is the only
#     integrity check the image gets over plain HTTP
#   * the written disk actually boots
#
# The last point matters most: `ghaf-installer` exiting 0 does not prove the
# disk is bootable, in the same way that a netboot server logging 200 for every
# artefact does not prove the target booted.
{ pkgs, self }:
let
  testConfig = "intel-laptop-debug";
  expectedHostname = "ghaf-host";

  cfg = self.nixosConfigurations.${testConfig};

  testingConfig = cfg.extendModules {
    modules = [
      (cfg._module.specialArgs.modulesPath + "/testing/test-instrumentation.nix")
      (cfg._module.specialArgs.modulesPath + "/profiles/qemu-guest.nix")
      (_: {
        testing.initrdBackdoor = true;
        services.openssh.enable = true;
      })
    ];
  };

  imagePath = testingConfig.config.system.build.ghafImage;
  targetPath = "/dev/vdb";

  # Matches what ghaf-netboot serves and what the ghaf.image_url= kernel
  # parameter points at: a base URL with ghaf-image.raw.zst and
  # ghaf-image.bmap directly beneath it.
  imageUrl = "http://server/ghaf-image";
in
pkgs.testers.nixosTest {
  name = "netboot-fetch-test";

  nodes = {
    # Stands in for ghaf-netboot's HTTP side. Only the layout matters, not the
    # server: the installer sees a plain base URL either way.
    server = _: {
      networking.firewall.allowedTCPPorts = [ 80 ];
      services.nginx = {
        enable = true;
        virtualHosts."server" = {
          locations."/ghaf-image/".alias = "${imagePath}/";
        };
      };
    };

    machine = _: {
      virtualisation.emptyDiskImages = [ (1024 * 256) ];
      virtualisation.memorySize = 1024 * 16;

      # UEFI, so /sys/firmware/efi/efivars exists and set_boot_to_disk actually
      # runs instead of degrading to its "no EFI variables" warning. That step
      # writes the target's NVRAM -- creating the boot entry and setting
      # BootNext -- and is what stops a netbooted machine coming straight back
      # into the installer, so it is the last part of the install that should be
      # covered only on hardware.
      virtualisation.useEFIBoot = true;

      # Drive this the way netboot actually does: through the KERNEL COMMAND
      # LINE, not an environment variable.
      boot.kernelParams = [
        "ghaf.image_url=${imageUrl}"
        "ghaf.install_target=${targetPath}"
        # Stay in the installer instead of rebooting into the result. An
        # unattended install ends with `systemctl reboot`, which would take the
        # machine away mid-assertion -- the test drives the reboot itself below.
        "ghaf.install_noreboot"
      ];

      environment.systemPackages = [
        self.packages.x86_64-linux.ghaf-installer
        self.packages.x86_64-linux.hardware-scan
        # For the test's own assertions. ghaf-installer carries its own copy via
        # runtimeInputs, so this does not stand in for that.
        pkgs.efibootmgr
      ];
    };
  };

  testScript = ''
    def create_test_machine(
        oldmachine=None, **kwargs
    ):  # taken from <nixpkgs/nixos/tests/installer.nix>
      assert oldmachine is not None, "create_test_machine requires oldmachine"
      start_command = [
          "${pkgs.qemu_test}/bin/qemu-kvm",
          "-cpu",
          "max",
          "-m",
          "16384",
          "-virtfs",
          "local,path=/nix/store,security_model=none,mount_tag=nix-store",
          "-drive",
          f"file={oldmachine.state_dir}/empty0.qcow2,id=drive1,if=none,index=1,werror=report",
          "-device",
          "virtio-blk-pci,drive=drive1",
          # UEFI support
          "-drive",
          "if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.firmware}",
          "-drive",
          "if=pflash,format=raw,unit=1,readonly=on,file=${pkgs.OVMF.variables}"
      ]
      machine = create_machine(start_command=" ".join(start_command), **kwargs)
      driver.machines.append(machine)
      return machine

    start_all()
    server.wait_for_unit("nginx.service")
    server.wait_for_open_port(80)

    with subtest("the image and its bmap are reachable over HTTP"):
        # If this fails the rest is noise, so check it before the install.
        machine.succeed("curl -sfI ${imageUrl}/ghaf-image.raw.zst >&2")
        # A missing bmap must be fatal rather than degrade to an unverified dd,
        # so its presence is part of the contract, not an optimisation.
        machine.succeed("curl -sfI ${imageUrl}/ghaf-image.bmap >&2")

    machine.succeed("lsblk >&2")

    with subtest("the kernel parameters reached the installer"):
        machine.succeed("grep -q 'ghaf.image_url=${imageUrl}' /proc/cmdline")
        machine.succeed("grep -q 'ghaf.install_target=${targetPath}' /proc/cmdline")

    with subtest("install over HTTP"):
        # bmaptool verifies each range's sha256 as it writes, so a corrupted or
        # truncated transfer fails here rather than producing a silent bad disk.
        #
        out = machine.succeed('ghaf-installer </dev/null', timeout=900)

    with subtest("the firmware is pointed at the disk that was just written"):
        # Without this the machine netboots again on the next reboot and comes
        # straight back into the installer -- which used to be prevented only by
        # the install server shutting itself down after one transfer, and cannot
        # be once one server is serving a fleet.
        assert "Boot loader on the ESP" in out, f"set_boot_to_disk did not run:\n{out}"
        # This node has never had a Linux boot entry, so the create branch is
        # the one that must fire. It is also the branch that aborted the whole
        # installer until the grep pipelines were guarded: under `set -euo
        # pipefail` a grep matching nothing is a fatal error, and "no matching
        # entry yet" is the normal state of a factory-fresh machine.
        assert "Creating boot entry" in out, f"boot entry not created:\n{out}"
        assert "BootNext set to Boot" in out, f"BootNext not set:\n{out}"

        # Assert on the firmware's own state, not on what the script said it did.
        entries = machine.succeed("efibootmgr -v")
        assert "Ghaf" in entries, f"no Ghaf boot entry in NVRAM:\n{entries}"
        assert "BootNext" in entries, f"BootNext not present in NVRAM:\n{entries}"
        # It must point at the disk we installed to, via the loader on its ESP.
        ghaf_line = [l for l in entries.splitlines() if "Ghaf" in l][0]
        assert "systemd-boot" in ghaf_line or "BOOT" in ghaf_line, (
            f"Ghaf entry does not name a loader:\n{ghaf_line}"
        )

    with subtest("a second install reuses the entry instead of duplicating it"):
        # NVRAM is small; a machine reinstalled repeatedly must not accumulate
        # identical entries until the firmware refuses to add more.
        before = len([l for l in machine.succeed("efibootmgr").splitlines() if "Ghaf" in l])
        out2 = machine.succeed('ghaf-installer </dev/null', timeout=900)
        assert "Reusing existing boot entry" in out2, f"entry not reused:\n{out2}"
        after = len([l for l in machine.succeed("efibootmgr").splitlines() if "Ghaf" in l])
        assert after == before, f"boot entries multiplied: {before} -> {after}"

    print("Shutting installer machine down")
    machine.shutdown()

    with subtest("the HTTP-installed disk boots"):
        new_machine = create_test_machine(oldmachine=machine, name="after_install")
        new_machine.start()
        new_machine.switch_root()
        new_machine.succeed("lsblk >&2")
        name = new_machine.succeed("cat /proc/sys/kernel/hostname").strip()
        assert name == "${expectedHostname}", f"expected hostname '${expectedHostname}', got {name}"
        new_machine.shutdown()
  '';
}
