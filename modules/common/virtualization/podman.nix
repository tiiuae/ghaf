# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, config, ... }:
let
  cfg = config.ghaf.virtualization.docker.daemon;
  inherit (lib) mkEnableOption mkIf;
in
{
  options.ghaf.virtualization.podman.daemon = {
    enable = mkEnableOption "Podman Daemon";
  };
  config = mkIf cfg.enable {
    # Just ensure containers are enabled by boot.
    boot.enableContainers = lib.mkForce true;

    # For CUDA support: Enable if not already enabled.
    ghaf.development.cuda.enable = lib.mkForce true;

    virtualisation.podman = {
      enable = true;
      # The enableNvidia option is still used in jetpack-nixos while it is obsolete in nixpkgs
      # but it is still only option for nvidia-orin devices.
      enableNvidia = (config.nixpkgs.localSystem.isAarch64 == true) && (config.hardware.nvidia-jetpack.enable == true);
      # Create a `docker` alias for podman, to use it as a drop-in replacement
      dockerCompat = (config.virtualisation.docker.enable == false);
      dockerSocket.enable = (config.virtualisation.docker.enable == false);
      # Required for containers under podman-compose to be able to talk to each other.
      defaultNetwork.settings.dns_enabled = true;
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
      
    # Enabling CDI NVIDIA devices in podman or docker (nvidia docker container)
    # For Orin devices this setting does not work as jetpack-nixos still does not support them.
    # jetpack-nixos uses enableNvidia = true; even though it is deprecated
    # For x86_64 the case is different it was introduced to be 
    # virtualisation.containers.cdi.dynamic.nvidia.enable = true;
    # but deprecated and changed to hardware.nvidia-container-toolkit.enable
    # We enable below setting if architecture ix x86_64 and if the video driver is nvidia set it true
    hardware.nvidia-container-toolkit.enable = (config.nixpkgs.localSystem.isx86_64 == true) &&
       (builtins.elem "nvidia" config.services.xserver.videoDrivers) ;

    # Enable Opengl renamed to hardware.graphics.enable
    hardware.graphics.enable = lib.mkForce true;

    # Add user to podman and docker group (due to compatibility mode) 
    # and dialout group for access to serial ports
    users.users."ghaf".extraGroups = ["docker" "dialout" "podman"];
  };
}