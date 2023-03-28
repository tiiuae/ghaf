{
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/minimal.nix")
  ];

  appstream.enable = false;

  systemd.package = pkgs.systemd.override {
    withCryptsetup = false;
    withDocumentation = false;
    withFido2 = false;
    withHomed = false;
    withHwdb = false;
    withLibBPF = true;
    withLocaled = false;
    withPCRE2 = false;
    withPortabled = false;
    withTpm2Tss = false;
    withUserDb = false;
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.enableContainers = false;
}
