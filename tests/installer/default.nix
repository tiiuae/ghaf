# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This is a main test for ghaf. If you want to debug it interactively
# you can follow this guide https://blog.thalheim.io/2023/01/08/how-to-execute-nixos-tests-interactively-for-debugging/.
# In other words, call breakpoint() at the point of testScript
# that you interested in to debug. After that you can build test driver using
# `nix build .#checks.x86_64-linux.installer.driver` and then run driver
# `./result/bin/nixos-test-driver`. Wait until the moment logs stop appear,
# after that you can execute `interact` and finally `new_machine.shell_interact()`.
# This will allow you to interact with installed ghaf.
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

  # FIXME: Only one attribute supported. What about ISO?
  imagePath = testingConfig.config.system.build.ghafImage;
  targetPath = "/dev/vdb";
  installerInput = pkgs.lib.strings.escapeNixString "${targetPath}\ny\ny\n";
in
pkgs.testers.nixosTest {
  name = "installer-test";
  nodes.machine = {
    virtualisation.emptyDiskImages = [ (1024 * 256) ];
    virtualisation.memorySize = 1024 * 16;

    environment.sessionVariables = {
      IMG_PATH = imagePath;
    };

    environment.systemPackages = [
      self.packages.x86_64-linux.ghaf-installer
      self.packages.x86_64-linux.hardware-scan
    ];
  };

  testScript = ''
    def create_test_machine(
        oldmachine=None, **kwargs
    ):  # taken from <nixpkgs/nixos/tests/installer.nix>
      # TODO: tpm2-abrmd.service fails to start. https://qemu-project.gitlab.io/qemu/specs/tpm.html
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

    machine.succeed("lsblk >&2")
    print(machine.succeed("tty"))
    machine.succeed('printf ${installerInput} | ghaf-installer', timeout=3600)
    print("Shutting installer image machine down")
    machine.shutdown()

    new_machine = create_test_machine(oldmachine=machine, name="after_install")
    new_machine.start()
    new_machine.switch_root() # Check documentation of options.testing.initrdBackdoor to understand why we need this.
    new_machine.succeed("lsblk >&2")
    print(new_machine.succeed("tty"))
    name = new_machine.succeed("cat /proc/sys/kernel/hostname").strip()
    assert name == "${expectedHostname}", f"expected hostname '${expectedHostname}', got {name}"
    new_machine.shutdown()
  '';
}
// {
  inherit testingConfig;
}
