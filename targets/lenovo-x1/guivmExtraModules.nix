# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  lib,
  pkgs,
  microvm,
  configH,
  ...
}: let
  openPdf = pkgs.callPackage ./openPdf.nix {
    inherit pkgs;
    inherit (configH.ghaf.security.sshKeys) sshKeyPath;
  };
  # TODO generalize this TCP port used by PDF XDG handler
  xdgPdfPort = 1200;

  winConfig = configH.ghaf.windows-launcher;

  guivmPCIPassthroughModule = {
    microvm.devices = lib.mkForce (
      builtins.map (d: {
        bus = "pci";
        inherit (d) path;
      })
      configH.ghaf.hardware.definition.gpu.pciDevices
    );
  };

  guivmVirtioInputHostEvdevModule = {
    microvm.qemu.extraArgs =
      builtins.concatMap (d: [
        "-device"
        "virtio-input-host-pci,evdev=${d}"
      ])
      configH.ghaf.hardware.definition.virtioInputHostEvdevs;
  };

  guivmExtraConfigurations = {
    ghaf.graphics.hardware.networkDevice = configH.ghaf.hardware.definition.network.pciDevices;
    ghaf.profiles.graphics.compositor = "labwc";
    ghaf.graphics.launchers = let
      hostAddress = "192.168.101.2";
      powerControl = pkgs.callPackage ../../packages/powercontrol {};
      powerControlIcons = pkgs.gnome.callPackage ../../packages/powercontrol/png-icons.nix {};
      privateSshKeyPath = configH.ghaf.security.sshKeys.sshKeyPath;
    in [
      {
        name = "chromium";
        path = "${pkgs.openssh}/bin/ssh -i ${privateSshKeyPath} -o StrictHostKeyChecking=no chromium-vm.ghaf run-waypipe chromium --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "${../../assets/icons/png/browser.png}";
      }

      {
        name = "gala";
        path = "${pkgs.openssh}/bin/ssh -i ${privateSshKeyPath} -o StrictHostKeyChecking=no gala-vm.ghaf run-waypipe gala --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "${../../assets/icons/png/app.png}";
      }

      {
        name = "zathura";
        path = "${pkgs.openssh}/bin/ssh -i ${privateSshKeyPath} -o StrictHostKeyChecking=no zathura-vm.ghaf run-waypipe zathura";
        icon = "${../../assets/icons/png/pdf.png}";
      }

      {
        name = "element";
        path = "${pkgs.openssh}/bin/ssh -i ${configH.ghaf.security.sshKeys.sshKeyPath} -o StrictHostKeyChecking=no element-vm.ghaf run-waypipe element-desktop --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "${../../assets/icons/png/element.png}";
      }

      {
        name = "appflowy";
        path = "${pkgs.openssh}/bin/ssh -i ${configH.ghaf.security.sshKeys.sshKeyPath} -o StrictHostKeyChecking=no appflowy-vm.ghaf run-waypipe appflowy";
        icon = "${../../assets/icons/svg/appflowy.svg}";
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
          inherit privateSshKeyPath;
        }}";
        icon = "${powerControlIcons}/${powerControlIcons.relativeShutdownIconPath}";
      }

      {
        name = "reboot";
        path = "${powerControl.makeRebootCommand {
          inherit hostAddress;
          inherit privateSshKeyPath;
        }}";
        icon = "${powerControlIcons}/${powerControlIcons.relativeRebootIconPath}";
      }

      # Temporarly disabled as it doesn't work stable
      # {
      #   path = powerControl.makeSuspendCommand {inherit hostAddress waypipeSshPublicKeyFile;};
      #   icon = "${adwaitaIconsRoot}/media-playback-pause-symbolic.symbolic.png";
      # }

      # Temporarly disabled as it doesn't work at all
      # {
      #   path = powerControl.makeHibernateCommand {inherit hostAddress waypipeSshPublicKeyFile;};
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
          ExecStart = "${openPdf}/bin/openPdf";
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

    microvm.qemu = {
      extraArgs =
      [
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
        ]
      ++ lib.optionals configH.ghaf.hardware.fprint.enable configH.ghaf.hardware.fprint.qemuExtraArgs;
    };
  };
in
  [
    guivmPCIPassthroughModule
    guivmVirtioInputHostEvdevModule
    guivmExtraConfigurations
  ]
  ++ lib.optionals configH.ghaf.hardware.fprint.enable [configH.ghaf.hardware.fprint.extraConfigurations]
