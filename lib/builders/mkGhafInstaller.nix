# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# mkGhafInstaller - Unified Ghaf Installer Builder
#
# Creates bootable ISO installers for Ghaf configurations.
# The installer NixOS system is evaluated once and shared across all targets.
# Per-target ISOs differ only in the embedded Ghaf image, which is injected
# via derivation override instead of a fresh NixOS evaluation.
#
# Usage:
#   let
#     ghafInstaller = ghaf.builders.mkGhafInstaller {
#       inherit self;
#       extraModules = [ ... ];
#     };
#   in ghafInstaller {
#     name = "lenovo-x1-carbon-gen11-debug";
#     imagePath = self.packages.x86_64-linux.lenovo-x1-carbon-gen11-debug;
#   }
#
# First-level parameters (evaluated once, shared across all installers):
#   self         - Flake self reference
#   lib          - Nixpkgs lib (default: self.lib)
#   system       - Target system architecture (default: "x86_64-linux")
#   extraModules - Additional NixOS modules for the installer system
#
# Second-level parameters (per target, no NixOS evaluation):
#   name         - Base name for the installer (e.g., "lenovo-x1-carbon-gen11-debug")
#   imagePath    - Path to the built Ghaf image package
#
# Output:
#   {
#     name    - Full installer name (e.g., "lenovo-x1-carbon-gen11-debug-installer")
#     package - The ISO image derivation
#   }
#
{
  self,
  lib ? self.lib,
  system ? "x86_64-linux",
  extraModules ? [ ],
}:
let
  # Evaluate the base installer NixOS system once. All per-target installers
  # reuse this evaluation via derivation override.
  baseInstallerConfig = lib.nixosSystem {
    specialArgs = {
      inherit lib;
    };
    modules = [
      (
        { pkgs, modulesPath, ... }:
        {
          imports = [
            "${toString modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
            # Enable plymouth graphical boot
            "${self}/modules/desktop/graphics/boot.nix"
          ];

          isoImage = {
            storeContents = [ ];
            contents = [ ];
            squashfsCompression = "zstd -Xcompression-level 3";
          };

          environment = {
            sessionVariables.IMG_PATH = "/iso/ghaf-image";
            variables.IMG_PATH = "/iso/ghaf-image";
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

          # Autostart the installer TUI on tty1, replacing the default getty
          systemd.services.ghaf-installer-tui = {
            description = "Ghaf Installer TUI";
            after = [ "multi-user.target" ];
            wantedBy = [ "multi-user.target" ];
            conflicts = [ "getty@tty1.service" ];
            environment = {
              IMG_PATH = "/iso/ghaf-image";
            };
            serviceConfig = {
              ExecStart = "${self.packages.${system}.ghaf-installer-tui}/bin/ghaf-installer-tui";
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
        }
      )
    ]
    ++ extraModules;
  };

  inherit (baseInstallerConfig) pkgs;
  baseIsoImage = baseInstallerConfig.config.system.build.isoImage;

  mkGhafInstaller =
    {
      name,
      imagePath,
    }:
    let
      normalizedImage = pkgs.runCommand "normalized-ghaf-image" { } ''
        mkdir -p $out
        imageFile=$(find ${imagePath} -maxdepth 1 -name "*.raw.zst" -type f | head -n 1)
        if [ -z "$imageFile" ]; then
          echo "Error: No .raw.zst file found in ${imagePath}" >&2
          exit 1
        fi
        cp --reflink=auto "$imageFile" $out/ghaf-image.raw.zst || \
          ln "$imageFile" $out/ghaf-image.raw.zst
      '';
    in
    {
      name = "${name}-installer";
      package = baseIsoImage.override {
        contents = baseInstallerConfig.config.isoImage.contents ++ [
          {
            source = "${normalizedImage}/ghaf-image.raw.zst";
            target = "/ghaf-image/ghaf-image.raw.zst";
          }
        ];
      };
    };
in
mkGhafInstaller
