# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  openssh,
  writeShellApplication,
}:
writeShellApplication {
  name = "ghaf-yubikey-ssh";
  runtimeInputs = [
    coreutils
    openssh # ssh-keygen with FIDO2/security-key (sk) support
  ];
  text = builtins.readFile ./yubikey-ssh.sh;
  meta = {
    description = "Enroll a FIDO2/YubiKey SSH key for Ghaf release SSH (ghaf.security.ssh.release)";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
