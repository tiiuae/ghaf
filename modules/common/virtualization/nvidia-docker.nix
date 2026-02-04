# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, config, ... }:
let
  cfg = config.ghaf.virtualization.nvidia-docker.daemon;
  inherit (lib) mkEnableOption mkIf;
in
{
  _file = ./nvidia-docker.nix;

  options.ghaf.virtualization.nvidia-docker.daemon = {
    enable = mkEnableOption "Nvidia Docker Daemon";
  };

  config = mkIf cfg.enable {
    # Enable Opengl renamed to hardware.graphics.enable
    hardware.graphics.enable = lib.mkForce true;

    # For CUDA support unfree libraries and CudaSupport should be set
    ghaf.development.cuda.enable = lib.mkForce true;

    # Enabling CDI NVIDIA devices in podman or docker (nvidia docker container)
    # We enable below setting if architecture ix x86_64 and if the video driver is nvidia set it true
    # or if architecture is aarch64 and nvidia-jetpack is enabled
    hardware.nvidia-container-toolkit.enable = lib.mkIf (
      (
        config.nixpkgs.hostPlatform.isx86_64
        && (builtins.elem "nvidia" config.services.xserver.videoDrivers)
      )
      || (config.nixpkgs.hostPlatform.isAarch64 && config.hardware.nvidia-jetpack.enable)
    ) true;

    # Temporary fix for nvidia service restart remove with new nixpkgs reference.
    # systemd.services.nvidia-container-toolkit-cdi-generator.WantedBy = [ "multi-user.target" ];
    systemd.services.nvidia-cdi-generate.after = [
      "multi-user.target"
      "greetd.service"
      "avahi-daemon.service"
    ];

    # Docker Daemon Settings
    virtualisation.docker = {
      # To force Docker package version settings need to import pkgs first
      # package = pkgs.docker_26;

      enable = true;
      daemon.settings.features.cdi = true;
      rootless = {
        enable = true;
        setSocketVariable = true;
        daemon.settings.features.cdi = true;
        daemon.settings.cdi-spec-dirs = [ "/var/run/cdi/" ];
      };

      # Container file and processor limits
      # daemon.settings = {
      #   default-ulimits = {
      #       nofile = {
      #       Name = "nofile";
      #       Hard = 1024;
      #       Soft = 1024;
      #       };
      #       nproc = {
      #       Name = "nproc";
      #       Soft = 65536;
      #       Hard = 65536;
      #       };
      #     };
      #   };
    };

    # Add user to docker group and dialout group for access to serial ports
    users.users."ghaf".extraGroups = [
      "docker"
      "dialout"
    ];
  };
}
