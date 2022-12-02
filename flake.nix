{
  description = "Ghaf - documentation for TII SSRC Common Tech";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
      flake-utils.lib.eachSystem systems (system: {

        packages =
          let
            pkgs = nixpkgs.legacyPackages.${system};
          in {
            doc = pkgs.callPackage ./doc.nix {};
          };

      });
}
