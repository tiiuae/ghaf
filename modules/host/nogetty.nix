# Slightly modified version of "${modulesPath}/profiles/headless.nix"
lib: {
  boot.kernelParams = let
    disableVESA = ["vga=0x317" "nomodeset"];
    rebootOnFail = ["panic=1" "boot.panic_on_fail"];
  in
    disableVESA ++ rebootOnFail;

  # Don't start a tty on the serial consoles.
  systemd.services."serial-getty@ttyS0".enable = lib.mkDefault false;
  systemd.services."serial-getty@hvc0".enable = false;
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@".enable = false;

  # Don't allow emergency mode, because we don't have a console.
  systemd.enableEmergencyMode = false;

  # Being headless, we don't need a GRUB splash image.
  boot.loader.grub.splashImage = null;
}
