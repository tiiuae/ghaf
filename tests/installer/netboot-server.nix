# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Test ghaf-netboot itself -- the server wrapper, not the artefacts it serves.
#
# netboot-boot.nix and netboot-fetch.nix both bypass this script entirely: the
# first boots the builder's artefacts through QEMU's own TFTP, the second serves
# the image with nginx. So the code that actually broke on 2026-08-01 -- the
# kernel command line ghaf-netboot.sh hands to pixiecore -- had no coverage at
# all, and neither of those tests would have caught it.
#
# What is asserted here, in rough order of how badly it hurt when it was wrong:
#
#   1. the assembled cmdline carries init= from netboot.ipxe. Omitting it put a
#      real machine into an emergency shell while every artefact was served 200.
#   2. the cleanup trap runs to completion. Under `set -o errexit` a kill of an
#      already-dead PID aborted the trap, leaving pixiecore running and the
#      firewall open after --exit-after-serve -- i.e. a destructive netboot
#      server still live on the LAN.
#   3. the guard rails refuse rather than proceed. The allowlist is the only
#      thing standing between "reinstall this machine" and "reinstall whichever
#      machine happened to PXE boot".
#   4. the iPXE binary we serve is our own snponly.efi and it carries the
#      embedded script. Both halves are load-bearing and fail differently:
#      pixiecore's built-in iPXE cannot get broadcast DHCP on the Lenovo dock
#      (recoverable only by unplugging it), and a binary without the embedded
#      "user-class pixiecore" line chainload-loops instead of booting.
#
# Deliberately fabricates its netboot/image directories: the point is to test
# the script's behaviour, not to re-test the builder.
{ pkgs, self }:
let
  # A recognisable stand-in for a real closure path, so the cmdline assertion
  # can be exact rather than a substring match on "init=".
  fakeInit = "/nix/store/0000000000000000000000000000000-nixos-system-fake/init";
in
pkgs.testers.nixosTest {
  name = "netboot-server-test";

  nodes.machine = {
    environment.systemPackages = [
      self.packages.x86_64-linux.ghaf-netboot
      pkgs.curl
      pkgs.file # identifying the iPXE binary as a real EFI application
      pkgs.binutils # strings, for the embedded-script assertion
    ];
    # pixiecore wants :67/:69/:4011; the serve subtest below is the only part
    # that needs them, and the VM is root anyway.
    networking.firewall.enable = false;
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # --- fixtures ---------------------------------------------------------
    machine.succeed("mkdir -p /tmp/nb /tmp/img")
    machine.succeed("echo fake-kernel > /tmp/nb/bzImage")
    machine.succeed("echo fake-initrd > /tmp/nb/initrd")
    # Shaped exactly like the builder's output, including the iPXE-only
    # placeholders that must not survive into the kernel cmdline.
    machine.succeed(
        "printf '%s\\n' '#!ipxe' "
        "'kernel bzImage init=${fakeInit} quiet root=fstab "
        "ghaf.image_url=http://''${next-server}/ghaf-images/x ''${cmdline}' "
        "'initrd initrd' 'boot' > /tmp/nb/netboot.ipxe"
    )
    machine.succeed("echo fake-image > /tmp/img/ghaf-image.raw.zst")
    machine.succeed("echo fake-bmap  > /tmp/img/ghaf-image.bmap")

    base = "ghaf-netboot -i eth1 -m aa:bb:cc:dd:ee:ff -n /tmp/nb -g /tmp/img --force-interface"

    with subtest("the cmdline is taken from netboot.ipxe, not invented"):
        # THE regression. Without init= the target boots into an emergency
        # shell and nothing server-side can tell.
        out = machine.succeed(f"{base} --dry-run 2>&1")
        assert "init=${fakeInit}" in out, f"init= missing from cmdline:\n{out}"
        # Carried over from the builder rather than re-guessed here.
        assert "root=fstab" in out, f"root=fstab missing from cmdline:\n{out}"

    with subtest("iPXE-only placeholders never reach the kernel"):
        out = machine.succeed(f"{base} --dry-run 2>&1")
        cmdline = [l for l in out.splitlines() if "cmdline" in l][0]
        # The next-server and cmdline placeholders are expanded by iPXE, not by
        # us. If they leak through, the kernel receives a literal dollar-brace
        # string instead of a URL.
        assert "next-server" not in cmdline, f"iPXE placeholder leaked:\n{cmdline}"
        assert "''${cmdline}" not in cmdline, f"iPXE placeholder leaked:\n{cmdline}"
        # Our URL must win over the builder's templated one.
        assert cmdline.count("ghaf.image_url=") == 1, f"duplicate image_url:\n{cmdline}"

    with subtest("a netboot dir without init= is refused, not served"):
        machine.succeed("mkdir -p /tmp/bad && cp /tmp/nb/bzImage /tmp/nb/initrd /tmp/bad/")
        machine.succeed(
            "printf '%s\\n' '#!ipxe' 'kernel bzImage quiet' 'initrd initrd' 'boot'"
            " > /tmp/bad/netboot.ipxe"
        )
        machine.fail(
            "ghaf-netboot -i eth1 -m aa:bb:cc:dd:ee:ff -n /tmp/bad -g /tmp/img"
            " --force-interface --dry-run"
        )

    with subtest("guard rails refuse rather than proceed"):
        # No allowlist: every PXE client on the LAN would be served.
        machine.fail("ghaf-netboot -i eth1 -n /tmp/nb -g /tmp/img --force-interface --dry-run")
        # A missing bmap must be fatal -- it is the only integrity check the
        # image gets over plain HTTP.
        machine.succeed("mkdir -p /tmp/nobmap && cp /tmp/img/ghaf-image.raw.zst /tmp/nobmap/")
        machine.fail(f"{base.replace('/tmp/img', '/tmp/nobmap')} --dry-run")
        # A malformed install target is destructive if it is wrong.
        machine.fail(f"{base} --install-target 'not-a-device' --dry-run")
        # An interface that does not exist.
        machine.fail("ghaf-netboot -i nosuchif0 -m aa:bb:cc:dd:ee:ff -n /tmp/nb -g /tmp/img --dry-run")
        # Missing netboot.ipxe entirely.
        machine.succeed("mkdir -p /tmp/noipxe && cp /tmp/nb/bzImage /tmp/nb/initrd /tmp/noipxe/")
        machine.fail(f"{base.replace('/tmp/nb', '/tmp/noipxe')} --dry-run")

    with subtest("the custom snponly.efi is the default, and it is real"):
        # Pixiecore's own iPXE drives NICs with native drivers and cannot get
        # broadcast DHCP on the Lenovo dock -- ten retries, then reboot, forever,
        # clearable only by unplugging the dock. Ours goes through the firmware's
        # SNP driver instead, so a silent regression back to the built-in would
        # reintroduce a failure that needs physical access to recover from.
        out = machine.succeed(f"{base} --dry-run 2>&1")
        ipxe = [l for l in out.splitlines() if l.strip().startswith("ipxe")][0]
        assert "snponly.efi" in ipxe, f"not defaulting to our iPXE:\n{ipxe}"
        path = ipxe.split()[1]
        machine.succeed(f"test -s {path}")
        # A PE32+ EFI application, not an empty file or a leftover shell wrapper.
        assert "PE32+" in machine.succeed(f"file -b {path}")
        # THE contract with pixiecore: option 77 user-class "pixiecore" is the
        # entire test it applies to decide it has already chainloaded a client
        # (pixiecore/dhcp.go). Without it pixiecore re-serves the binary in an
        # endless ~20 s chainload loop, which is how a stock iPXE fails here.
        machine.succeed(f"strings -a {path} | grep -q 'set user-class pixiecore'")

    with subtest("--ipxe builtin falls back, --ipxe <missing> refuses"):
        # The escape hatch, for a NIC the firmware's SNP does not cover.
        out = machine.succeed(f"{base} --ipxe builtin --dry-run 2>&1")
        ipxe = [l for l in out.splitlines() if l.strip().startswith("ipxe")][0]
        assert "snponly.efi" not in ipxe, f"--ipxe builtin ignored:\n{ipxe}"
        assert "pixiecore built-in" in ipxe, f"--ipxe builtin ignored:\n{ipxe}"
        # A typo'd path must not silently degrade to pixiecore's iPXE.
        machine.fail(f"{base} --ipxe /nonexistent/snponly.efi --dry-run")

    with subtest("--exit-after-serve defaults on for an unattended install"):
        # The installer reboots itself when an unattended install finishes, and
        # a netbooted target usually has network boot ahead of its disk -- so a
        # server still answering PXE catches that reboot and reinstalls the
        # machine, looping on the single most expensive operation there is.
        out = machine.succeed(f"{base} --install-target /dev/nvme0n1 --dry-run 2>&1")
        stop = [l for l in out.splitlines() if l.strip().startswith("stop")][0]
        assert "served in full" in stop, f"not defaulting to --exit-after-serve:\n{stop}"

        # Interactive runs must NOT inherit it. Nothing fetches the image, and
        # an operator stepping through the TUI needs the server to stay up.
        out = machine.succeed(f"{base} --dry-run 2>&1")
        stop = [l for l in out.splitlines() if l.strip().startswith("stop")][0]
        assert "timeout or signal" in stop, f"interactive must not exit after serve:\n{stop}"

        # Opting out stays possible, but has to say what it costs.
        out = machine.succeed(
            f"{base} --install-target /dev/nvme0n1 --no-exit-after-serve --dry-run 2>&1"
        )
        assert "reinstall itself on every reboot" in out, f"loop hazard unflagged:\n{out}"

    with subtest("--dry-run starts nothing"):
        machine.succeed(f"{base} --dry-run")
        machine.fail("pgrep -x pixiecore")

    with subtest("--exit-after-serve stops the server AND cleans up"):
        # The cleanup-trap bug: the API shuts itself down, so by the time the
        # trap runs $API_PID is already dead; under errexit a bare `kill` of it
        # aborted the trap and left pixiecore running with ports bound.
        machine.succeed(f"{base} --exit-after-serve -t 5 >/tmp/srv.log 2>&1 &")
        machine.wait_until_succeeds("grep -q 'ready. Boot the target' /tmp/srv.log", timeout=60)
        machine.succeed("pgrep -x pixiecore")

        ip = machine.succeed("ip -4 -br addr show eth1 | awk '{print $3}' | cut -d/ -f1").strip()
        machine.succeed(f"curl -sf http://{ip}:8080/ghaf-image/ghaf-image.raw.zst -o /dev/null")

        machine.wait_until_succeeds("grep -q 'image served in full' /tmp/srv.log", timeout=60)
        # Everything below here is what the trap is for.
        machine.wait_until_fails("pgrep -x pixiecore", timeout=60)
        machine.wait_until_succeeds("grep -q 'ghaf-netboot: stopped' /tmp/srv.log", timeout=60)
        machine.fail("ss -lnup | grep -E ':(67|69|4011)\\b'")
  '';
}
