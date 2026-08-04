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

  # cfg.enable alone. This used to also require nvidia-setup.enable as a
  # stand-in for "the host owns the backlight", but hybrid-setup enables that on
  # plain Intel laptops, so the forwarder was created on machines with no virtio
  # port to write to. The platform now states it via hostBacklight instead.
  config = mkIf cfg.enable {

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
        # acpid too: acpi_listen connects to its socket, and without ordering
        # the first start loses that race and fails.
        after = [
          "dev-virtio\\x2dports-brightness.device"
          "acpid.service"
        ];
        # `after` only orders. This stops the unit starting at all when the
        # device never appears, so a mismatch is inert rather than restart-looping.
        unitConfig.ConditionPathExists = "/dev/virtio-ports/brightness";
        serviceConfig = {
          Type = "simple";
          ExecStart = "${brightnessForwarder}/bin/brightness-forwarder";
          Restart = "always";
          RestartSec = "1";
        };
      };
  };
}
