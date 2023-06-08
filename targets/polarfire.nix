{
  self,
  nixpkgs-22-11,
  nixos-hardware-tii,
}:
let
  name = "mpfs-icicle-kit";
  system = "riscv64-linux";
  nixpkgs = nixpkgs-22-11;
  nixos-hardware = nixos-hardware-tii;
  hardware-modules = [
    nixos-hardware.nixosModules.polarfire-hardenedos
    ../modules/hardware/polarfire/mpfs-nixos-sdimage.nix
    ../modules/development/ssh.nix
    ../modules/development/authentication.nix
    ./headless-common.nix
    #../modules/development/docker.nix
    (import ../modules/vanilla-host {
            inherit self;
          })
    {
      nixpkgs = {
         localSystem.config = "x86_64-unknown-linux-gnu";
         crossSystem.config = "riscv64-unknown-linux-gnu";
      };

      boot.kernelParams = [ "root=/dev/mmcblk0p2" "rootdelay=5"  ];
      boot.consoleLogLevel = 4;
      boot.loader = {
        grub.enable = false;
        generic-extlinux-compatible.enable = true;
      };
    }
  ];

  release-configuration = nixpkgs.lib.nixosSystem {
    modules = hardware-modules ++ [./headless-release.nix];
  };

  debug-configuration = nixpkgs.lib.nixosSystem {
    modules = hardware-modules ++ [./headless-debug.nix];
  };

  nixos-configurations = {
    icicle-kit-rel = release-configuration;
    icicle-kit-deb = debug-configuration;
  };
in
{
  packages = {
    riscv64-linux = {
        mpfs-icicle-kit-release = nixos-configurations.icicle-kit-rel.config.system.build.sdImage;
        mpfs-icicle-kit-debug = nixos-configurations.icicle-kit-deb.config.system.build.sdImage;
     };
  };
}

