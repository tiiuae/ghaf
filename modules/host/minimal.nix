{
  pkgs,
  lib,
  ...
}:
with lib; {
  environment.noXlibs = mkDefault true;

  documentation.enable = mkDefault false;

  documentation.nixos.enable = mkDefault false;

  programs.command-not-found.enable = mkDefault false;

  xdg.autostart.enable = mkDefault false;
  xdg.icons.enable = mkDefault false;
  xdg.mime.enable = mkDefault false;
  xdg.sounds.enable = mkDefault false;

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

  boot.enableContainers = false;
}
