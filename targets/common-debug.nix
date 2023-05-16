# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Common modules for all debug-targets
{
  imports = [
    ./common.nix

    #### on-host development supporting modules ####
    # drop/replace modules below this line for any real use
    ../modules/development/authentication.nix
    ../modules/development/nix.nix
    ../modules/development/packages.nix
    ../modules/development/ssh.nix
    ../modules/development/docker.nix
  ];
}
