{
  self,
  nixpkgs,
  nixos-generators,
  nixos-hardware,
}: let
  name = "mpfs-icicle-kit";
  system = "riscv64-linux";
  hardware-modules = [ 
                       nixos-hardware.nixosModules.microchip-icicle-kit
                       ../modules/hardware/polarfire/configuration.nix
                       ../modules/hardware/polarfire/mpfs-nixos-sdimage.nix
                       ../modules/hardware/polarfire/base-packages.nix
                       ];
  base-configuration = nixpkgs.lib.nixosSystem {
        modules = hardware-modules;
    };

  debug-configuration = nixpkgs.lib.nixosSystem {
        modules = hardware-modules ++ [../modules/hardware/polarfire/debug-packages.nix];
    };

  nixos-configurations = {
      icicle-kit-rel = base-configuration;
      icicle-kit-deb = debug-configuration;
   };
in {
  packages = {
    riscv64-linux = {
        mpfs-icicle-kit-release = nixos-configurations.icicle-kit-rel.config.system.build.sdImage;
        mpfs-icicle-kit-debug = nixos-configurations.icicle-kit-deb.config.system.build.sdImage;
     };
  };
}

