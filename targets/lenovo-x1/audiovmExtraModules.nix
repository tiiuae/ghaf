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
  # TCP port used by Pipewire-pulseaudio service
  pulseaudioTcpPort = 4713;

  audiovmPCIPassthroughModule = {
    microvm.devices = lib.mkForce (
      builtins.map (d: {
        bus = "pci";
        inherit (d) path;
      })
      configH.ghaf.hardware.definition.audio.pciDevices
    );
  };

  audiovmExtraConfigurations = {
    ghaf.hardware.definition.network.pciDevices = configH.ghaf.hardware.definition.network.pciDevices;

    time.timeZone = "Asia/Dubai";

    # Enable pipewire service for audioVM with pulseaudio support
    security.rtkit.enable = true;
    sound.enable = true;

    services.pipewire = {
      enable = true;
      #      alsa.enable = true;
      #      alsa.support32Bit = true;
      pulse.enable = true;
      systemWide = true;
    };

    environment.etc."pipewire/pipewire.conf.d/10-remote-simple.conf".text = ''
      context.modules = [
        {   name = libpipewire-module-protocol-pulse
            args = {
              server.address = [
                  "tcp:4713"    # IPv4 and IPv6 on all addresses
              ];
              pulse.min.req          = 128/48000;     # 2.7ms
              pulse.default.req      = 960/48000;     # 20 milliseconds
              pulse.min.frag         = 128/48000;     # 2.7ms
              pulse.default.frag     = 512/48000;     # ~10 ms
              pulse.default.tlength  = 512/48000;     # ~10 ms
              pulse.min.quantum      = 128/48000;     # 2.7ms
            }
        }
      ]
    '';

    # Allow ghaf user to access pulseaudio and pipewire
    users.extraUsers.ghaf.extraGroups = ["audio" "video" "pulse-access" "pipewire"];

    # Dummy service to get pipewire and pulseaudio services started at boot
    # Normally Pipewire and pulseaudio are started when they are needed by user,
    # We don't have users in audiovm so we need to give PW/PA a slight kick..
    # This calls pulseaudios pa-info binary to get information about pulseaudio current
    # state which starts pipewire-pulseaudio service in the process.

    systemd.services.pulseaudio-starter = {
      after = ["pipewire.service" "network-online.target"];
      requires = ["pipewire.service"];
      wantedBy = ["default.target"];
      path = [pkgs.coreutils];
      enable = true;
      serviceConfig = {
        User = "ghaf";
        Group = "ghaf";
      };
      script = ''${pkgs.pulseaudio}/bin/pa-info > /dev/null 2>&1'';
    };

    # Open TCP port for the PDF XDG socket
    networking.firewall.allowedTCPPorts = [pulseaudioTcpPort];

    microvm.qemu.extraArgs = [
    ];
  };
in [
  ./sshkeys.nix
  audiovmPCIPassthroughModule
  audiovmExtraConfigurations
]
