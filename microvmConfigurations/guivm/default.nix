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

      microvm.hypervisor = "qemu";

      nixpkgs.overlays = [
        (self: super: {
          qemu_kvm = super.qemu_kvm.overrideAttrs (self: super: {
            patches = super.patches ++ [./qemu-aarch-memory.patch];
          });
        })
      ];

      networking.enableIPv6 = false;
      networking.interfaces.eth0.useDHCP = true;
      networking.firewall.allowedTCPPorts = [22];

      environment.systemPackages = with pkgs; [
        weston
      ];

      hardware.nvidia.open = false;
      hardware.nvidia.modesetting.enable = true;
      nixpkgs.config.allowUnfree = true;
      services.xserver.videoDrivers = ["nvidia"];
      hardware.opengl.enable = true;
      hardware.opengl.driSupport = true;

      boot.kernelParams = [
        "pci=nomsi"
      ];
      
      microvm.interfaces = [
        {
          type = "tap";
          id = "vm-guivm";
          mac = "02:00:00:01:01:01";
        }
      ];
    })
  ];
}
