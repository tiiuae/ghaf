{
  self,
  jetpack-nixos,
  microvm,
}: rec {
  system = "aarch64-linux";
  modules = [
    jetpack-nixos.nixosModules.default
    ../modules/hardware/nvidia-jetson-orin.nix

    microvm.nixosModules.host
    ../configurations/host/configuration.nix
    ../configurations/host/networking.nix
    (import ../configurations/host/microvm.nix {
      inherit self system;
    })

    #### on-host development supporting modules ####
    # drop/replace modules below this line for any real use
    ../modules/development/authentication.nix
    ../modules/development/ssh.nix
    ../modules/development/nix.nix
    ../modules/development/packages.nix
  ];
}
