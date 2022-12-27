{
  pkgs = import <nixpkgs> {
    overlays = [
      (import ./overlays/common.nix)
      (import ./overlays/intel-nuc.nix)
    ];
  };
}
