# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{pkgs, ...}: let
  authorizedKeys = [
    # Add your SSH Public Keys here
    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIA/pwHnzGNM+ZU4lANGROTRe2ZHbes7cnZn72Oeun/MCAAAABHNzaDo= brian@arcadia"
  ];
in {
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = authorizedKeys;
  users.users.ghaf.openssh.authorizedKeys.keys = authorizedKeys;
}
