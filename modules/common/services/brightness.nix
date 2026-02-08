# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.ghaf.services.brightness;
  nvidiaEnabled = config.ghaf.graphics.nvidia-setup.enable;
in
{
  _file = ./brightness.nix;

  options.ghaf.services.brightness = {
    enable = mkEnableOption "brightness controlling via VirtIO";

    socketPath = mkOption {
      type = types.path;
      default = "/tmp/brightness.sock";
      description = "The path where the socket needs to be created.";
    };
  };

  # Currently we need acpi forwarder for NVidia platform where acpi is enabled
  config = mkIf (cfg.enable && nvidiaEnabled) {

    assertions = [
      {
        assertion = config.services.acpid.enable;
        message = "Please enable acpid service or disable brightness service";
      }
    ];

    systemd.services."brightness-acpi-forwarder" =
      let
        brightnessForwarder = pkgs.writeShellApplication {
          name = "brightness-forwarder";
          runtimeInputs = [ pkgs.acpid ];
          text = ''
            acpi_listen | while read -r event; do
              case "$event" in
                *BRTUP*)
                  echo "+5" > /dev/virtio-ports/brightness
                  ;;
                *BRTDN*)
                  echo "5-" > /dev/virtio-ports/brightness
                  ;;
              esac
            done
          '';
        };
      in
      {
        enable = true;
        description = "ACPI Brightness Key Forwarder to Host via VirtIO";
        wantedBy = [ "multi-user.target" ];
        # Start after /dev/virtio-ports/brightness (systemd escapes '-' as \x2d in unit names)
        after = [ "dev-virtio\\x2dports-brightness.device" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${brightnessForwarder}/bin/brightness-forwarder";
          Restart = "always";
          RestartSec = "1";
        };
      };
  };
}
