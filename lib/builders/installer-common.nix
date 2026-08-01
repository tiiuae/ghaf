# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# installer-common - the media-agnostic half of the Ghaf installer
#
# Everything the installer needs regardless of how it was booted: the TUI unit,
# plymouth, the installer packages, hostname and getty text. The media layer on
# top adds the boot medium and says where the image lives:
#
#   mkGhafInstaller.nix         ISO   -> imageSource = "/iso/ghaf-image"
#   mkGhafNetbootInstaller.nix  PXE   -> imageSource = an http(s) URL
#
# WHY THIS IS A SEPARATE MODULE RATHER THAN ONE SHARED nixosSystem:
# ISO and netboot cannot coexist in a single evaluation. nixpkgs'
# installer/cd-dvd/iso-image.nix and installer/netboot/netboot.nix both define
# config.lib.isoFileSystems."/nix/.ro-store".device at the same priority (and
# disagree on image.extension / image.filePath / system.build.image), so
# importing both is a conflicting-definition error. Sharing therefore has to
# mean sharing a *module*, evaluated twice, rather than one system built twice.
#
# KEEP THE TWO BUILDERS IN SYNC: anything added directly to mkGhafInstaller.nix
# that is not genuinely ISO-specific will silently be missing from the netboot
# installer. If it is not about the boot medium, it belongs here.
#
# Takes `self` and `system` at import time rather than reading them from module
# arguments: the builders construct their nixosSystem with
# `specialArgs = { inherit lib; }` only, so there is no `self` in scope inside
# the modules themselves.
{
  self,
  system,
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.installer;
in
{
  imports = [
    # Enable plymouth graphical boot
    "${self}/modules/desktop/graphics/boot.nix"
  ];

  options.ghaf.installer.imageSource = lib.mkOption {
    type = lib.types.str;
    default = "/iso/ghaf-image";
    example = "http://192.0.2.1:8080/ghaf-image";
    description = ''
      Where ghaf-installer and ghaf-installer-tui look for ghaf-image.raw.zst
      and ghaf-image.bmap.

      A local directory (the ISO case) or an http(s) base URL (the netboot
      case). Exported as IMG_PATH; the installer scripts branch on the scheme.
      A `ghaf.image_url=` kernel parameter overrides it at runtime, which is how
      one netboot artefact can serve every target.
    '';
  };

  config = {
    environment = {
      sessionVariables.IMG_PATH = cfg.imageSource;
      variables.IMG_PATH = cfg.imageSource;
    };

    ghaf.graphics.boot = {
      enable = true;
      renderer = "simpledrm";
    };

    # Skip NixOS installer
    boot.loader.timeout = lib.mkForce 0;

    systemd.services.wpa_supplicant.wantedBy = lib.mkForce [ "multi-user.target" ];
    systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];
    networking.networkmanager.enable = true;

    image.baseName = lib.mkForce "ghaf";
    networking.hostName = "ghaf-installer";

    environment.systemPackages = [
      self.packages.${system}.ghaf-installer-tui
      self.packages.${system}.ghaf-installer
      self.packages.${system}.hardware-scan
    ];

    # Autostart the installer on tty1, replacing the default getty.
    systemd.services.ghaf-installer-tui = {
      description = "Ghaf Installer";
      after = [ "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];
      conflicts = [ "getty@tty1.service" ];
      environment = {
        IMG_PATH = cfg.imageSource;
      };
      serviceConfig = {
        ExecStart = pkgs.writeShellScript "ghaf-installer-autostart" ''
          # ghaf-installer reads ghaf.install_target/_encrypt/_secureboot and
          # ghaf.image_url itself, so the dispatch here is only about which of
          # the two front-ends to run.
          if grep -q 'ghaf\.install_target=' /proc/cmdline 2>/dev/null; then
            echo "ghaf.install_target= on the kernel command line: installing unattended." >&2
            exec ${self.packages.${system}.ghaf-installer}/bin/ghaf-installer
          fi
          exec ${self.packages.${system}.ghaf-installer-tui}/bin/ghaf-installer-tui
        '';
        # Suppress kernel printk noise on tty1 while TUI is active
        ExecStartPre = "${pkgs.util-linux}/bin/dmesg -n 1";
        # Restore kernel log level and hand tty1 back to getty on exit
        ExecStopPost = [
          "${pkgs.util-linux}/bin/dmesg -n 7"
          "${pkgs.systemd}/bin/systemctl start getty@tty1.service"
        ];
        StandardInput = "tty";
        StandardOutput = "tty";
        StandardError = "tty";
        TTYPath = "/dev/tty1";
        TTYReset = true;
        TTYVHangup = true;
        PrivateTmp = true;
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    services.getty = {
      greetingLine = "<<< Welcome to the Ghaf installer >>>";
      helpLine = lib.mkAfter ''

        To start the interactive Ghaf installer, run
        `sudo ghaf-installer-tui`.

        To start the non-interactive Ghaf installer, run
        `sudo ghaf-installer`.
      '';
    };

    # NOTE: Stop nixos complains about "warning:
    # mdadm: Neither MAILADDR nor PROGRAM has been set. This will cause the `mdmon` service to crash."
    # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/profiles/installation-device.nix#L112
    boot.swraid.mdadmConf = "PROGRAM ${pkgs.coreutils}/bin/true";

    boot = {
      kernelPackages = pkgs.linuxPackages_latest;
      # Disable ZFS support - not compatible with latest. only supported on LTS.
      supportedFilesystems.zfs = lib.mkForce false;
    };

    # Configure nixpkgs with Ghaf overlays for extended lib support
    nixpkgs = {
      hostPlatform.system = system;
      config = {
        allowUnfree = true;
        permittedInsecurePackages = [
          "jitsi-meet-1.0.8043"
          "qtwebengine-5.15.19"
        ];
      };
      overlays = [ self.overlays.default ];
    };
  };
}
