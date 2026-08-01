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
  testConfig = "lenovo-x1-carbon-gen11-debug";
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
  installerInput = pkgs.lib.strings.escapeNixString "${targetPath}\ny\ny\n";

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

      # The netboot equivalent of the ISO's local directory. This is the one
      # thing that differs from tests/installer/default.nix.
      environment.sessionVariables = {
        IMG_PATH = imageUrl;
      };

      environment.systemPackages = [
        self.packages.x86_64-linux.ghaf-installer
        self.packages.x86_64-linux.hardware-scan
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
    with subtest("install over HTTP"):
        # bmaptool verifies each range's sha256 as it writes, so a corrupted or
        # truncated transfer fails here rather than producing a silent bad disk.
        #
        # Measured at 110.7 s on a 128-core dev host with NVMe (whole test:
        # 171.6 s). This step decompresses and writes several GB, so it is the
        # one place where a slow or IO-constrained runner genuinely needs room --
        # 900 s is ~8x measured. The ISO test next door still uses 3600 s, which
        # predates any measurement; worth retuning it from its own log rather
        # than copying either number forward on faith.
        machine.succeed('printf ${installerInput} | ghaf-installer', timeout=900)

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
