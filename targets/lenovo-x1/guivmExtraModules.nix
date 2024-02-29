# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  pkgs,
  microvm,
  hostConfiguration,
  ...
}: let
  openPdf = pkgs.callPackage ./openPdf.nix {
    inherit pkgs;
    inherit (config.ghaf.security.sshKeys) sshKeyPath;
  };
  # TCP port used by PDF XDG handler
  xdgPdfPort = 1200;

  winConfig = hostConfiguration.config.ghaf.windows-launcher;
in {
  imports = [./sshkeys.nix];
  ghaf.hardware.definition.network.pciDevices = hostConfiguration.config.ghaf.hardware.definition.network.pciDevices;
  ghaf.graphics.launchers = let
    adwaitaIconsRoot = "${pkgs.gnome.adwaita-icon-theme}/share/icons/Adwaita/32x32/actions/";
    hostAddress = "192.168.101.2";
    powerControl = pkgs.callPackage ../../packages/powercontrol {};
  in [
    {
      name = "chromium";
      path = "${pkgs.openssh}/bin/ssh -i ${config.ghaf.security.sshKeys.sshKeyPath} -o StrictHostKeyChecking=no chromium-vm.ghaf run-waypipe chromium --enable-features=UseOzonePlatform --ozone-platform=wayland";
      icon = "${../../assets/icons/png/browser.png}";
    }

    {
      name = "gala";
      path = "${pkgs.openssh}/bin/ssh -i ${config.ghaf.security.sshKeys.sshKeyPath} -o StrictHostKeyChecking=no gala-vm.ghaf run-waypipe gala --enable-features=UseOzonePlatform --ozone-platform=wayland";
      icon = "${../../assets/icons/png/app.png}";
    }

    {
      name = "zathura";
      path = "${pkgs.openssh}/bin/ssh -i ${config.ghaf.security.sshKeys.sshKeyPath} -o StrictHostKeyChecking=no zathura-vm.ghaf run-waypipe zathura";
      icon = "${../../assets/icons/png/pdf.png}";
    }

    {
      name = "windows";
      path = "${pkgs.virt-viewer}/bin/remote-viewer -f spice://${winConfig.spice-host}:${toString winConfig.spice-port}";
      icon = "${../../assets/icons/png/windows.png}";
    }

    {
      name = "nm-launcher";
      path = "${pkgs.nm-launcher}/bin/nm-launcher";
      icon = "${pkgs.networkmanagerapplet}/share/icons/hicolor/22x22/apps/nm-device-wwan.png";
    }

    {
      name = "poweroff";
      path = "${powerControl.makePowerOffCommand {
        inherit hostAddress;
        inherit (config.ghaf.security.sshKeys) sshKeyPath;
      }}";
      icon = "${adwaitaIconsRoot}/system-shutdown-symbolic.symbolic.png";
    }

    {
      name = "reboot";
      path = "${powerControl.makeRebootCommand {
        inherit hostAddress;
        inherit (config.ghaf.security.sshKeys) sshKeyPath;
      }}";
      icon = "${adwaitaIconsRoot}/system-reboot-symbolic.symbolic.png";
    }

    # Temporarly disabled as it doesn't work stable
    # {
    #   path = powerControl.makeSuspendCommand {inherit hostAddress sshKeyPath;};
    #   icon = "${adwaitaIconsRoot}/media-playback-pause-symbolic.symbolic.png";
    # }

    # Temporarly disabled as it doesn't work at all
    # {
    #   path = powerControl.makeHibernateCommand {inherit hostAddress sshKeyPath;};
    #   icon = "${adwaitaIconsRoot}/media-record-symbolic.symbolic.png";
    # }
  ];

  time.timeZone = "Asia/Dubai";

  # PDF XDG handler service receives a PDF file path from the chromium-vm and executes the openpdf script
  systemd.user = {
    sockets."pdf" = {
      unitConfig = {
        Description = "PDF socket";
      };
      socketConfig = {
        ListenStream = "${toString xdgPdfPort}";
        Accept = "yes";
      };
      wantedBy = ["sockets.target"];
    };

    services."pdf@" = {
      description = "PDF opener";
      serviceConfig = {
        ExecStart = "${openPdf}/bin/openpdf";
        StandardInput = "socket";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };
  };

  # Open TCP port for the PDF XDG socket
  networking.firewall.allowedTCPPorts = [xdgPdfPort];
  # Early KMS needed for GNOME to work inside GuiVM
  boot.initrd.kernelModules = ["i915"];

  microvm.qemu.extraArgs = [
    # Lenovo X1 Lid button
    "-device"
    "button"
    # Lenovo X1 battery
    "-device"
    "battery"
    # Lenovo X1 AC adapter
    "-device"
    "acad"
    # Connect sound device to hosts pulseaudio socket
    "-audiodev"
    "pa,id=pa1,server=unix:/run/pulse/native"
  ];
}
