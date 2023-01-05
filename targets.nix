{
  self,
  nixos-generators,
  microvm,
  jetpack-nixos,
}: {
  packages.x86_64-linux.vm = nixos-generators.nixosGenerate {
    system = "x86_64-linux";
    modules = [
      microvm.nixosModules.host
      configurations/host/configuration.nix
      modules/development/authentication.nix
    ];
    format = "vm";
  };

  packages.x86_64-linux.default = self.packages.x86_64-linux.vm;

  packages.aarch64-linux.nvidia-jetson-orin = nixos-generators.nixosGenerate {
    system = "aarch64-linux";
    modules = [
      jetpack-nixos.nixosModules.default
      modules/hardware/nvidia-jetson-orin.nix

      microvm.nixosModules.host
    ];
    format = "raw-efi";
  };

  # Using Orin as a default aarch64 target for now
  packages.aarch64-linux.default = self.packages.aarch64-linux.nvidia-jetson-orin;
}
