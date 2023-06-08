{ config, pkgs, modulesPath, lib, ...}:
{
  imports = [
    (modulesPath + "/profiles/minimal.nix")
  ];

  /* General */
  /* ======= */
  disabledModules = [ "profiles/all-hardware.nix" ];
}
