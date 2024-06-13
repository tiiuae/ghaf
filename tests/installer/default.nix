# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  self,
}: let
  testConfig = "lenovo-x1-carbon-gen11-debug";
  system = "x86_64-linux";
  expectedHostname = "ghaf-host";

  target = self.outputs.nixosConfigurations.${testConfig};

  dependencies =
    [
      target.config.system.build.toplevel
      target.config.system.build.diskoScript
      target.pkgs.stdenv.drvPath
      (target.pkgs.closureInfo {rootPaths = [];}).drvPath
    ]
    ++ builtins.map (i: i.outPath) (builtins.attrValues self.inputs);

  closureInfo = pkgs.closureInfo {rootPaths = dependencies;};

  diskoInstall = self.inputs.disko.packages.${system}.disko-install;
  installScript = pkgs.callPackage ../../packages/installer {
    inherit diskoInstall;
    targetName = testConfig;
    ghafSource = self;

    # Suppose that we have only one "main" disk required
    diskName = with builtins; head (attrNames target.config.ghaf.hardware.definition.disks);
  };
in
  pkgs.nixosTest {
    name = "installer-test";
    nodes.machine = {
      virtualisation.emptyDiskImages = [(1024 * 16)];
      virtualisation.memorySize = 1024 * 8;
      environment.etc.installClosure.source = "${closureInfo}/store-paths";
      environment.systemPackages = [installScript];
    };

    testScript = ''
      def create_test_machine(oldmachine, args={}): # taken from <nixpkgs/nixos/tests/installer.nix>
          startCommand = "${pkgs.qemu_test}/bin/qemu-kvm"
          startCommand += " -cpu max -m 1024 -virtfs local,path=/nix/store,security_model=none,mount_tag=nix-store"
          startCommand += f" -drive file={oldmachine.state_dir}/empty0.qcow2,id=drive1,if=none,index=1,werror=report"
          startCommand += " -device virtio-blk-pci,drive=drive1"
          startCommand += " -drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.firmware}"
          startCommand += " -drive if=pflash,format=raw,unit=1,readonly=on,file=${pkgs.OVMF.variables}"
          machine = create_machine({
            "startCommand": startCommand,
          } | args)
          driver.machines.append(machine)
          return machine
      machine.succeed("lsblk >&2")

      print(machine.succeed("tty"))

      machine.succeed("DEVICE_PATH='/dev/vdb' unshare -n ghaf-installer.sh")
      machine.shutdown()

      # # FIXME: boot stucks
      # new_machine = create_test_machine(oldmachine=machine, args={ "name": "after_install" })
      # new_machine.start()
      # name = new_machine.succeed("hostname").strip()
      # assert name == "${expectedHostname}", f"expected hostname '${expectedHostname}', got {name}"
      # new_machine.shutdown()
    '';
  }
