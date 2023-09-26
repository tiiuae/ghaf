{
  self,
  lib,
  nixpkgs,
  disko,
}: let
  release = lib.strings.fileContents ../.version;
  versionSuffix = ".${lib.substring 0 8 (self.lastModifiedDate or self.lastModified or "19700101")}.${self.shortRev or "dirty"}";
  version = release + versionSuffix;
in {
  inherit release versionSuffix version;
  modules = import ./ghaf-modules.nix {inherit lib;};

  # NOTE: Currently supports configuration that generates raw-efi image using nixos-generators
  installer = {
    systemImgCfg,
    modules ? [],
    userCode ? "",
  }: let
    system = systemImgCfg.nixpkgs.hostPlatform.system;

    pkgs = import nixpkgs {inherit system;};

    installerScript = import ../modules/installer/installer.nix {
      inherit pkgs;
      inherit (pkgs) runtimeShell;
      inherit userCode;
    };

    diskoCLI = disko.packages.x86_64-linux.disko;
    partitioning = pkgs.callPackage ../modules/installer/partitioning.nix {};

    installerImgCfg = lib.nixosSystem {
      inherit system;
      specialArgs = {inherit lib;};
      modules =
        [
          ../modules/host

          ({modulesPath, ...}: {
            imports = [(modulesPath + "/profiles/all-hardware.nix")];

            nixpkgs.hostPlatform.system = system;
            nixpkgs.config.allowUnfree = true;

            hardware.enableAllFirmware = true;

            ghaf.profiles.installer.enable = true;
          })

          {
            environment.systemPackages = [installerScript diskoCLI];
            environment.loginShellInit = ''
              ln -s ${partitioning}/partitioning-scheme "$HOME/partitioning-scheme"
              ln -s ${partitioning}/example_secret.key "$HOME/example_secret.key"
              installer.sh
            '';
          }
        ]
        ++ (import ../modules/module-list.nix)
        ++ modules;
    };
  in {
    inherit installerImgCfg system;
    installerImgDrv = installerImgCfg.config.system.build.${installerImgCfg.config.formatAttr};
  };
}
