{modulesPath, ...}: {
  imports = [
    (modulesPath + "/profiles/minimal.nix")
  ];
  networking.hostName = "ghaf-host";
  system.stateVersion = "22.11";
}
