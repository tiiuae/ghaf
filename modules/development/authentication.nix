{pkgs, ...}:
# account for the development time login with sudo rights
let
  user = "ghaf";
  password = "ghaf";
in {
  users = {
    mutableUsers = true;
    users."${user}" = {
      isNormalUser = true;
      password = password;
      extraGroups = [ "wheel" ];
    };
  };
}
