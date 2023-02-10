{pkgs, ...}: {
  hardware.opengl = {
    enable = true;
    driSupport = true;
  };

  environment.noXlibs = false;
  environment.systemPackages = with pkgs; [
    weston
  ];
}
