# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  ...
}:
let
  useGivc = config.ghaf.givc.enable;
  cfg = config.ghaf.services.audio;
  host = "audio-vm";
  port =
    if cfg.client.pipewireControl.enable then
      cfg.server.pulseaudioTcpControlPort
    else
      cfg.server.pulseaudioTcpPort;
  address = "tcp:${host}:${toString port}";

in
{
  _file = ./client.nix;

  options.ghaf.services.audio = {
    client = {
      remotePulseServerAddress = lib.mkOption {
        type = lib.types.str;
        default = address;
        defaultText = address;
        description = ''
          Address of the remote PulseAudio server to connect to.

          This should point to the main Ghaf audio server.
        '';
      };
      pipewireControl = {
        enable = lib.mkEnableOption ''
          PipeWire control forwarding to gui-vm client.

          This allows gui-vm to control audio settings via PipeWire.
          Requires givc to be enabled on both client and server.

          To use it, set the `PIPEWIRE_RUNTIME_DIR` environment variable to /tmp.
          `PIPEWIRE_RUNTIME_DIR` can be set for the entire session but is not recommended,
          as it may interfere with local PipeWire instances.
        '';
        socket = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default = "/tmp/pipewire-0";
          description = ''
            Path where the PipeWire socket is available for control operations.
          '';
        };
      };
    };
  };
  config = lib.mkIf (cfg.enable && (cfg.role == "client")) (
    lib.mkMerge [
      {
        environment = {
          systemPackages = [ pkgs.pulseaudio ];
          sessionVariables = {
            PULSE_SERVER = "${cfg.client.remotePulseServerAddress}";
          };
          variables = {
            PULSE_SERVER = "${cfg.client.remotePulseServerAddress}";
          };
        };
      }
      # givc socket proxy is declared in modules/givc/guivm.nix
      (lib.mkIf (cfg.client.pipewireControl.enable && useGivc) {
        assertions = [
          {
            assertion = config.system.name == "gui-vm";
            message = "PipeWire control forwarding can only be enabled on gui-vm.";
          }
          {
            assertion = useGivc;
            message = "GIVC must be enabled on audio clients when enabling Ghaf audio server control forwarding.";
          }
        ];

        environment = {
          systemPackages = with pkgs; [
            pipewire
            # `pwwvucontrol` is a good Rust-based alternative for pure PipeWire
            # but it lacks some features and polish compared to `pavucontrol`
            pavucontrol
          ];
        };
      })
    ]
  );
}
