{
  self,
  nixos-generators,
  microvm,
  jetpack-nixos,
}: rec {
  packages.x86_64-linux.vm = nixos-generators.nixosGenerate rec {
    system = "x86_64-linux";
    modules = [
      (import ../modules/host {
        inherit self microvm system;
      })

      ../modules/graphics/weston.nix

      #### on-host development supporting modules ####
      # drop/replace modules below this line for any real use
      ../modules/development/authentication.nix
      ../modules/development/nix.nix
      ../modules/development/packages.nix
      ../modules/development/ssh.nix
    ];
    format = "vm";
  };

  packages.x86_64-linux.intel-nuc = nixos-generators.nixosGenerate rec {
    system = "x86_64-linux";
    modules = [
      (import ../modules/host {
        inherit self microvm system;
      })

      ../modules/graphics/weston.nix

      #### on-host development supporting modules ####
      # drop/replace modules below this line for any real use
      ../modules/development/authentication.nix
      ../modules/development/intel-nuc-getty.nix
      ../modules/development/nix.nix
      ../modules/development/ssh.nix
    ];
    format = "raw-efi";
  };

  packages.x86_64-linux.default = self.packages.x86_64-linux.vm;

  packages.aarch64-linux.nvidia-jetson-orin = nixos-generators.nixosGenerate (
    import ./nvidia-jetson-orin.nix {inherit self jetpack-nixos microvm;}
    // {
      format = "raw-efi";
    }
  );

  # Using Orin as a default aarch64 target for now
  packages.aarch64-linux.default = self.packages.aarch64-linux.nvidia-jetson-orin;
}
