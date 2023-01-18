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

   #### on-host development supporting modules ####
   # drop/replace modules below this line for any real use
    ../modules/development/authentication.nix
    ../modules/development/ssh.nix
    ../modules/development/nix.nix
  ];
}
