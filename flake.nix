{
  description = "Ghaf - Documentation and implementation for TII SSRC Secure Technologies Ghaf Framework";

  nixConfig = {
    extra-substituters = [
      "https://cache.vedenemo.dev"
      "https://cache.ssrcdevops.tii.ae"
    ];
    extra-trusted-public-keys = [
      "cache.vedenemo.dev:RGHheQnb6rXGK5v9gexJZ8iWTPX6OcSeS56YeXYzOcg="
      "cache.ssrcdevops.tii.ae:oOrzj9iCppf+me5/3sN/BxEkp5SaFkHfKTPPZ97xXQk="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.11";
    flake-utils.url = "github:numtide/flake-utils";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    jetpack-nixos = {
      url = "github:anduril/jetpack-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , nixos-generators
    , microvm
    , jetpack-nixos
    ,
    }:
    let
      systems = with flake-utils.lib.system; [
        x86_64-linux
        aarch64-linux
      ];
    in
    # Combine list of attribute sets together
    nixpkgs.lib.foldr nixpkgs.lib.recursiveUpdate { } [
      # Documentation
      (flake-utils.lib.eachSystem systems (system: {
        packages =
          let
            pkgs = nixpkgs.legacyPackages.${system};
          in
          {
            doc = pkgs.callPackage ./docs/doc.nix { };
          };

        formatter = nixpkgs.legacyPackages.${system}.alejandra;
      }))
      # Final target images
      (import ./targets.nix { inherit self nixos-generators microvm jetpack-nixos; })
    ];
}
