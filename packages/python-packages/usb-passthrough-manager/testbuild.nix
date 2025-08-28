# default.nix
{
  pkgs ? import <nixpkgs> { },
}:
pkgs.python3Packages.callPackage ./package.nix { }
