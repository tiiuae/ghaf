{
  jetpack-nixos,
  microvm,
}: {
  system = "aarch64-linux";
  modules = [
    jetpack-nixos.nixosModules.default
    ../modules/hardware/nvidia-jetson-orin.nix

    microvm.nixosModules.host
    ../configurations/host/configuration.nix
    ../modules/development/authentication.nix
  ];
}
