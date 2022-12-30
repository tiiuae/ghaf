{
  description = "Ghaf - documentation for TII SSRC Common Tech";

  nixConfig = {
    extra-substituters = [
      "https://cache.vedenemo.dev"
    ];
    extra-trusted-public-keys = [
      "cache.vedenemo.dev:RGHheQnb6rXGK5v9gexJZ8iWTPX6OcSeS56YeXYzOcg="
    ];
  };

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-22.11";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }: let
    systems = with flake-utils.lib.system; [
      x86_64-linux
      aarch64-linux
    ];
  in
    flake-utils.lib.eachSystem systems (system: {
      packages = let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        doc = pkgs.callPackage ./doc.nix {};
      };

      formatter = nixpkgs.legacyPackages.${system}.alejandra;
    });
}
