# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  _file = ./default.nix;

  imports = [
    ./nvidia-docker.nix
    ./nvidia-podman.nix
    ./storagevm-encryption.nix
  ];
}
