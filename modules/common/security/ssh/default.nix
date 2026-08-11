# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# ghaf.security.ssh - Ghaf's SSH posture. SSH is a security-relevant service present in
# both profiles, so it lives here rather than under ghaf.development:
#   - ghaf.security.ssh.debug   : unprotected sshd (password + dev keys), debug images
#   - ghaf.security.ssh.release : hardened, certificate/key-only sshd, release images
{ lib, ... }:
{
  _file = ./default.nix;

  imports = [
    ./debug.nix
    ./release.nix
    # Back-compat: ghaf.development.ssh.daemon.enable was renamed to
    # ghaf.security.ssh.debug.enable when SSH moved out of the development namespace.
    (lib.mkRenamedOptionModule
      [ "ghaf" "development" "ssh" "daemon" "enable" ]
      [ "ghaf" "security" "ssh" "debug" "enable" ]
    )
  ];
}
