{
  pkgs,
  self,
}: let
  testConfig = "lenovo-x1-carbon-gen11-debug";
  expectedHostname = "ghaf";
  disk = "disk1";

  diskoInstall = self.inputs.disko.packages.x86_64-linux.disko-install;

  dependencies =
    [
      pkgs.stdenv.drvPath
      self.outputs.nixosConfigurations.${testConfig}.config.system.build.toplevel
      self.outputs.nixosConfigurations.${testConfig}.config.system.build.diskoScript
    ]
    ++ builtins.map (i: i.outPath) (builtins.attrValues self.inputs);

  closureInfo = pkgs.closureInfo {rootPaths = dependencies;};
in
  pkgs.nixosTest {
    name = "installer-test";
    nodes.machine = {
      virtualisation.emptyDiskImages = [(4096 * 2)];
      virtualisation.memorySize = 3000 * 2;
      environment.etc.installClosure.source = "${closureInfo}/store-paths";
      environment.systemPackages = [diskoInstall];
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

    machine.succeed("disko-install --disk ${disk} /dev/vdb --flake ${self}#${testConfig}")
    machine.shutdown()

      # # FIXME: boot stucks
      # new_machine = create_test_machine(oldmachine=machine, args={ "name": "after_install" })
      # new_machine.start()
      # name = new_machine.succeed("hostname").strip()
      # assert name == "${expectedHostname}", f"expected hostname '${expectedHostname}', got {name}"
      # new_machine.shutdown()
    '';
  }
