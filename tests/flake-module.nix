{self, ...}: {
  flake.checks = let
    pkgsPerSystem = system: self.inputs.nixpkgs.legacyPackages.${system};
  in {
    x86_64-linux = let
      pkgs = pkgsPerSystem "x86_64-linux";
    in {
      installer = pkgs.callPackage ./installer {inherit self;};
    };
  };
}
