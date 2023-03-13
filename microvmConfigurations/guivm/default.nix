{
  nixpkgs,
  microvm,
  system,
}:
nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    # TODO: Enable only for development builds
    ../../modules/development/authentication.nix
    ../../modules/development/ssh.nix
    ../../modules/development/packages.nix

    microvm.nixosModules.microvm

    ({pkgs, ...}: {
      networking.hostName = "guivm";
      # TODO: Maybe inherit state version
      system.stateVersion = "22.11";

      # For WLAN firmwares
      hardware.enableRedistributableFirmware = true;

      microvm.hypervisor = "qemu";

      networking.enableIPv6 = false;
      networking.interfaces.eth0.useDHCP = true;
      networking.firewall.allowedTCPPorts = [22];

      environment.systemPackages = with pkgs; [
        weston
      ];
      environment.variables = {
        WAYLAND_DISPLAY = "wayland-1";
        XDG_RUNTIME_DIR = "/run/user/1000";
      };
      hardware.opengl.enable = true;
      hardware.opengl.driSupport = true;

      microvm.interfaces = [
        {
          type = "tap";
          id = "vm-guivm";
          mac = "02:00:00:01:01:01";
        }
      ];

      networking.wireless = {
        enable = true;

        # networks."SSID_OF_NETWORK".psk = "WPA_PASSWORD";
      };


      #boot.kernelModules = ["drm" "virtio_gpu"];
    })
  ];
}
