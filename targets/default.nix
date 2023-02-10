{
  self,
  nixos-generators,
  microvm,
  jetpack-nixos,
}: {
  packages.x86_64-linux.vm = nixos-generators.nixosGenerate (
    import ./vm.nix {inherit self microvm;} // {format = "vm";}
  );

  packages.x86_64-linux.intel-nuc = nixos-generators.nixosGenerate (
    import ./vm.nix {inherit self microvm;} // {format = "raw-efi";}
  );

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
