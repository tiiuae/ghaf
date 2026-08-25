# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# A standing Ghaf install server.
#
# This is NOT a Ghaf-device module. It configures an ordinary NixOS machine --
# a lab or provisioning box -- to serve netboot installs to a fleet, which is
# why it lives outside modules/common and is not part of any Ghaf profile.
#
# The CLI (`ghaf-netboot`) remains the right tool for a one-off install at a
# desk. This is for the case it cannot cover: a server that stays up across many
# machines and many hours.
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.services.netboot-server;
in
{
  options.ghaf.services.netboot-server = {
    enable = lib.mkEnableOption "the Ghaf netboot install server";

    package = lib.mkOption {
      type = lib.types.package;
      example = lib.literalExpression "ghaf.packages.x86_64-linux.ghaf-netboot";
      description = ''
        The ghaf-netboot package to run.

        Required rather than defaulted: ghaf-netboot is built by pkgs-by-name
        into `packages.<system>`, not added to any overlay, so it is not in
        `pkgs` on the server importing this module. Pass it from the ghaf flake
        directly.
      '';
    };

    interface = lib.mkOption {
      type = lib.types.str;
      example = "eno2";
      description = ''
        Interface facing the machines being installed. There is deliberately no
        default: picking the wrong NIC is the whole hazard, and on a server the
        mistake is standing rather than momentary.
      '';
    };

    netbootDir = lib.mkOption {
      type = lib.types.path;
      description = "Result of .#<target>-netboot-installer (bzImage, initrd, netboot.ipxe).";
    };

    imageDir = lib.mkOption {
      type = lib.types.path;
      description = "Result of .#<target> (ghaf-image.raw.zst and ghaf-image.bmap).";
    };

    macs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "48:21:0b:9e:06:d5" ];
      description = "Machines allowed to boot. Combines with {option}`macFile`.";
    };

    macFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        A roster file, one MAC per line, `#` for comments. This is what makes a
        hundred-machine run practical, and it is what lets the server report
        that every machine on the roster has finished.
      '';
    };

    anyMac = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Serve every machine that PXE boots on {option}`interface`, with no
        allowlist at all.

        Reasonable on a dedicated provisioning network, where collecting a
        hundred MAC addresses in advance is friction with no safety return. Not
        reasonable anywhere else: a machine only reaches this server while it is
        actively PXE booting, but plenty of machines emit a PXE request on every
        boot and fall through to disk when nothing answers. One of those
        rebooting during a run gets an unattended, destructive install.

        `ghaf-netboot` refuses this on the interface carrying the default route
        unless {option}`forceInterface` is also set.
      '';
    };

    installTarget = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/dev/nvme0n1";
      description = ''
        Install unattended to this device on every machine served. DESTRUCTIVE.
        Null serves the interactive TUI instead.
      '';
    };

    encrypt = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "With {option}`installTarget`, enable disk encryption.";
    };

    secureboot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "With {option}`installTarget`, enroll Secure Boot keys.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = ''
        HTTP port. Note that `port + 1` is used by pixiecore and is opened too
        when {option}`openFirewall` is set.
      '';
    };

    maxConcurrentImages = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8;
      description = ''
        How many machines may download the disk image at once.

        Everything else -- the boot API, kernel, initrd and block map -- is never
        queued, because a machine waiting at that stage is still in firmware and
        iPXE gives up after ten DHCP attempts. Only the multi-GB image is
        staggered, and clients over the cap wait and retry.

        Raising this does not move more bytes; it divides the same link between
        more machines. The useful value is roughly "how many can finish at a
        speed that does not trip their own timeouts".
      '';
    };

    retryAfter = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "Seconds a queued client is told to wait before retrying.";
    };

    forceInterface = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Skip the refusals for a default-route or wireless interface. A lab
        server whose only NIC carries its default route needs this.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open 67/69/4011 and the HTTP ports declaratively.

        Deliberately not the CLI's `--open-firewall`: that adds entries to the
        `nixos-fw temp-ports` set and removes them again on exit, which is right
        for an interactive run and wrong for a service that is supposed to be
        up. Without PXE reaching the server at all, everything looks healthy
        while every machine times out.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra arguments appended to the ghaf-netboot invocation.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.anyMac || cfg.macs != [ ] || cfg.macFile != null;
        message = ''
          ghaf.services.netboot-server: set macs, macFile or anyMac. Without one
          of them the server would install any machine that PXE boots on
          ${cfg.interface}.
        '';
      }
      {
        assertion = !(cfg.anyMac && (cfg.macs != [ ] || cfg.macFile != null));
        message = ''
          ghaf.services.netboot-server: anyMac serves everything, so an
          allowlist alongside it is contradictory.
        '';
      }
      {
        assertion = (cfg.encrypt || cfg.secureboot) -> cfg.installTarget != null;
        message = ''
          ghaf.services.netboot-server: encrypt and secureboot only apply to an
          unattended install; set installTarget as well.
        '';
      }
    ];

    networking.firewall = lib.mkIf cfg.openFirewall {
      # 67 DHCP, 69 TFTP (the iPXE binary), 4011 ProxyDHCP.
      allowedUDPPorts = [
        67
        69
        4011
      ];
      allowedTCPPorts = [
        cfg.port
        (cfg.port + 1)
      ];
    };

    systemd.services.ghaf-netboot-server = {
      description = "Ghaf netboot install server";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        # Root is unavoidable: DHCP/PXE need 67, 69 and 4011, and a DHCP server
        # must answer clients that have no address yet.
        User = "root";
        Restart = "on-failure";
        # ghaf-netboot refuses to start when the interface has no carrier, which
        # is the correct answer to an unplugged cable -- and makes the service
        # self-heal once it is plugged back in, rather than needing a manual
        # start. Long enough not to spin.
        RestartSec = "15s";
        ExecStart = lib.escapeShellArgs (
          [
            (lib.getExe cfg.package)
            "--interface"
            cfg.interface
            "--netboot"
            "${cfg.netbootDir}"
            "--image"
            "${cfg.imageDir}"
            "--port"
            (toString cfg.port)
            "--max-concurrent-images"
            (toString cfg.maxConcurrentImages)
            "--retry-after"
            (toString cfg.retryAfter)
            # A daemon is exactly the case the 60-minute default exists to catch
            # (someone forgetting a server and carrying the laptop away), so it
            # has to be turned off explicitly rather than inherited.
            "--timeout"
            "0"
          ]
          ++ lib.concatMap (m: [
            "--mac"
            m
          ]) cfg.macs
          ++ lib.optionals (cfg.macFile != null) [
            "--mac-file"
            "${cfg.macFile}"
          ]
          ++ lib.optional cfg.anyMac "--any-mac"
          ++ lib.optionals (cfg.installTarget != null) [
            "--install-target"
            cfg.installTarget
          ]
          ++ lib.optional cfg.encrypt "--encrypt"
          ++ lib.optional cfg.secureboot "--secureboot"
          ++ lib.optional cfg.forceInterface "--force-interface"
          ++ cfg.extraArgs
        );
      };
    };
  };
}
