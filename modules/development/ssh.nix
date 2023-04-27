# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{pkgs, ...}: let
  authorizedKeys = [
    # Add your SSH Public Keys here
    # NOTE: adding your pub ssh key here will make accessing and "nixos-rebuild switching" development mode
    # builds easy but still secure. Given that you protect your private keys. Do not share your keypairs across hosts.
    #
    # Shared authorized keys access poses a minor risk for developers in the same network (e.g. office) cross-accessing
    # each others development devices if:
    # - the ip addresses from dhcp change between the developers without the noticing AND
    # - you ignore the server fingerprint checks
    # You have been helped and you have been warned.
    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIA/pwHnzGNM+ZU4lANGROTRe2ZHbes7cnZn72Oeun/MCAAAABHNzaDo= brian@arcadia"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDdNDuKwAsAff4iFRfujo77W4cyAbfQHjHP57h/7tJde ville.ilvonen@unikie.com"
  ];
in {
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = authorizedKeys;
  users.users.ghaf.openssh.authorizedKeys.keys = authorizedKeys;
}
