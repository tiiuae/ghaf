{pkgs, ...}: let
  authorizedKeys = [
    # Add your SSH Public Keys here
    # "ssh-ed25519 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA user@host"
  ];
in {
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = authorizedKeys;
  users.users.ghaf.openssh.authorizedKeys.keys = authorizedKeys;
}
