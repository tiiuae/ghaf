# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Boot the netboot installer over PXE and assert it actually reaches the
# installer -- not merely that the artefacts were transferred.
#
# This test exists because of a real failure. The netboot server can serve every
# artefact with a 200 and log a flawless sequence while the target sits in an
# emergency shell: on 2026-08-01 an X1 did exactly that, because the kernel
# command line was assembled by hand and omitted
# `init=/nix/store/...-nixos-system-.../init`, so `initrd-find-nixos-closure`
# had nothing to switch into. Nothing server-side could see it; it was caught by
# someone photographing the screen.
#
# Hence the assertions below are deliberately about the *booted system*:
#
#   - ghaf-installer-tui.service is active   (only true if stage-2 was reached)
#   - init= is on /proc/cmdline              (the specific regression)
#   - ghaf.image_url= is on /proc/cmdline    (the installer knows where to fetch)
#
# Modelled on nixpkgs nixos/tests/boot.nix `makeNetbootTest`, which is the
# working OVMF+iPXE reference: QEMU's user-mode network provides DHCP and TFTP,
# `-boot order=n` boots from it, and the iPXE option ROM drives the UEFI path.
{ pkgs, self }:
let
  inherit (self.inputs) nixpkgs;
  system = "x86_64-linux";

  netbootInstaller = self.builders.mkGhafNetbootInstaller {
    inherit self system;
    inherit (self) lib;
    extraModules = [
      self.nixosModules.laptop-installer
      "${nixpkgs}/nixos/modules/testing/test-instrumentation.nix"
      { key = "serial"; }
    ];
  };

  # A literal URL rather than the default `http://${next-server}/...`: iPXE would
  # expand that to QEMU's gateway, which is fine but makes the assertion depend
  # on QEMU's addressing. Pinning it keeps the check about our plumbing.
  imageUrl = "http://10.0.2.2:8080/ghaf-image";

  # bzImage, initrd and netboot.ipxe -- exactly the layout a TFTP root needs, and
  # exactly what ghaf-netboot serves.
  tftpRoot =
    (netbootInstaller {
      name = "netboot-boot-test";
      inherit imageUrl;
    }).package;

  startCommand = builtins.concatStringsSep " " [
    "${pkgs.qemu_test}/bin/qemu-kvm"
    "-cpu max"
    # The initrd is ~637 MiB and is resident, with the store unpacked alongside
    # it. Anything tight here fails as an opaque stage-1 OOM.
    "-m 8192"
    "-netdev user,id=net0,tftp=${tftpRoot},bootfile=netboot.ipxe"
    "-device virtio-net-pci,netdev=net0,romfile=${pkgs.ipxe}/ipxe.efirom"
    "-boot order=n"
    # Secure Boot is off in these OVMF variables, which matches the documented
    # precondition for netboot: the chain is unsigned, exactly as the ISO is.
    "-drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.firmware}"
    "-drive if=pflash,format=raw,unit=1,readonly=on,file=${pkgs.OVMF.variables}"
  ];
in
pkgs.testers.nixosTest {
  name = "netboot-boot-test";
  nodes = { };

  testScript = ''
    machine = create_machine("${startCommand}")
    machine.start()

    machine.wait_for_unit("multi-user.target", timeout=500)

    with subtest("the installer actually started"):
        # The assertion that distinguishes a booted installer from an emergency
        # shell. Everything below is detail; this is the test.
        # Measured at 0.01 s once multi-user.target is up -- it is ordered after
        # it -- so this timeout is pure headroom.
        machine.wait_for_unit("ghaf-installer-tui.service", timeout=120)

    with subtest("init= reached the kernel"):
        # The 2026-08-01 regression, stated directly.
        machine.succeed("grep -q 'init=/nix/store/' /proc/cmdline")

    with subtest("the installer knows where to fetch the image"):
        # Only the cmdline is asserted here. IMG_PATH comes from
        # ghaf.installer.imageSource, a build-time default, and is *overridden*
        # at runtime from ghaf.image_url by the installer scripts -- so checking
        # the environment would be testing the wrong layer.
        machine.succeed("grep -q 'ghaf.image_url=${imageUrl}' /proc/cmdline")

    machine.shutdown()
  '';
}
