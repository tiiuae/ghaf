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
    ../../user-apps/default.nix
    ../../modules/graphics/weston.nix
    ../../modules/windows/launcher.nix

    microvm.nixosModules.microvm

    ({
      config,
      pkgs,
      lib,
      ...
    }: {
      networking.hostName = "guivm";
      # TODO: Maybe inherit state version
      system.stateVersion = lib.trivial.release;

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

      hardware.nvidia.modesetting.enable = true;
      nixpkgs.config.allowUnfree = true;
      services.xserver.videoDrivers = ["nvidia"];
      hardware.opengl.enable = true;
      hardware.opengl.driSupport = true;
      hardware.nvidia.open = false;
      hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.beta;

      boot.kernelParams = [
        "pci=nomsi"
      ];

      microvm.interfaces = [
        {
          type = "tap";
          id = "vm-guivm";
          mac = "02:00:00:02:01:01";
        }
      ];
    })
  ];
}
