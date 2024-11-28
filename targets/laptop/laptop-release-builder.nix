{
  self,
  lib,
  inputs,
  ...
}:
let
  pkgs = import inputs.nixpkgs {
    inherit inputs;

    system = "x86_64-linux";
  };

  roothashPlaceholder = "61fe0f0c98eff2a595dd2f63a5e481a0a25387261fa9e34c37e3a4910edf32b8";

  imageOverride =
    image:
    image.config.system.build.image.overrideAttrs (oldAttrs: {
      nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [ pkgs.jq ];
      postInstall = ''
        # Extract the roothash from the JSON
        repartRoothash="$(
          ${lib.getExe pkgs.jq} -r \
            '[.[] | select(.roothash != null)] | .[0].roothash' \
            "$out/repart-output.json"
        )"

        # Replace the placeholder with the real roothash in the target .raw file
        sed -i \
          "0,/${roothashPlaceholder}/ s/${roothashPlaceholder}/$repartRoothash/" \
          "$out/${oldAttrs.pname}_${oldAttrs.version}.raw"
      '';
    });

  mkReleaseLaptopConfiguration =
    machineType: variant: split: extraModules:
    let
      hostConfiguration = lib.nixosSystem {
        modules = [
          self.nixosModules.profiles
          self.nixosModules.profiles-laptop
          self.nixosModules.laptop
          self.nixosModules.microvm
          self.nixosModules.mem-manager

          (
            {
              modulesPath,
              ...
            }:
            {
              ghaf = {
                profiles = {
                  # variant type, turn on debug or release
                  debug.enable = true;
                };
                hardware.definition = import ../../modules/reference/hardware/lenovo-x1/definitions/x1-gen11.nix;
                reference.profiles.mvp-user-trial.enable = true;
                reference.profiles.mvp-user-trial-extras.enable = true;
              };

              boot.kernelParams = [
                "roothash=${roothashPlaceholder}"
              ];

              boot.initrd.systemd.initrdBin = [
                pkgs.less
                pkgs.util-linux
              ];

              image.repart.split = split;

              nixpkgs = {
                hostPlatform.system = "x86_64-linux";

                # Increase the support for different devices by allowing the use
                # of proprietary drivers from the respective vendors
                config = {
                  allowUnfree = true;
                  #jitsi was deemed insecure because of an obsecure potential security
                  #vulnerability but it is still used by many people
                  permittedInsecurePackages = [
                    "jitsi-meet-1.0.8043"
                  ];
                };
                overlays = [ self.overlays.default ];
              };

              imports = [
                ../../modules/common/disk
                "${modulesPath}/image/repart.nix"
                "${modulesPath}/system/boot/uki.nix"
              ];
            }
          )
        ] ++ extraModules;
      };
    in
    {
      inherit hostConfiguration;
      variant = "debug";
      name = "${machineType}-${variant}";
      package = imageOverride hostConfiguration;
    };
in
mkReleaseLaptopConfiguration
