# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Common modules for all debug-targets
{
  imports = [
    ./common.nix

    #### on-host development supporting modules ####
    # drop/replace modules below this line for any real use
    ../modules/users/accounts.nix
    {
      ghaf.users.accounts.enable = true;
    }
    ../modules/development/nix.nix
    {
      ghaf.development.nix-setup.enable = true;
    }
    ../modules/development/debug-tools.nix
    {
      ghaf.development.debug.tools.enable = true;
    }
    ../modules/development/ssh.nix
    {
      ghaf.development.ssh.daemon.enable = true;
    }
  ];
}
