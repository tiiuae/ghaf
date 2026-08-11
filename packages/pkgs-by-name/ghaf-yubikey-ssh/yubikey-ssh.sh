# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=bash
# Enroll a FIDO2/YubiKey SSH key for Ghaf release SSH.
# The resulting public key goes into ghaf.security.ssh.release.authorizedKeys.
set -euo pipefail

keyfile="$HOME/.ssh/ghaf_yubikey_ed25519_sk"
comment="${USER:-ghaf}@$(uname -n 2>/dev/null || echo host)-ghaf-$(date +%Y%m%d)"
keytype="ed25519-sk"
resident=1
verify=1

usage() {
  cat <<EOF
ghaf-yubikey-ssh - enroll a FIDO2/YubiKey SSH key for Ghaf release SSH

Usage: ghaf-yubikey-ssh [options]

Options:
  -c, --comment TEXT   key comment (default: ${comment})
  -f, --file PATH      output key path (default: ${keyfile})
      --ecdsa          use ecdsa-sk instead of ed25519-sk (for tokens whose
                       firmware predates ed25519-sk support, < 5.2.3)
      --no-resident    do not store the credential on the token
                       (default is resident, so it can be re-imported with
                       'ssh-keygen -K' onto a fresh client)
      --no-verify      drop verify-required (no per-login PIN/touch). Only for a
                       deliberately vaulted-style recovery key; weakens the
                       default posture and needs
                       authorizedKeysOptions="restrict,pty,port-forwarding"
                       (port-forwarding is required to reach a VM through the net-vm jump).
  -h, --help           show this help

Insert your YubiKey first. You will be asked to touch it (and to enter its FIDO2
PIN). The printed public key is what you paste into the release target's config.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
  -c | --comment)
    comment="$2"
    shift 2
    ;;
  -f | --file)
    keyfile="$2"
    shift 2
    ;;
  --ecdsa)
    keytype="ecdsa-sk"
    shift
    ;;
  --no-resident)
    resident=0
    shift
    ;;
  --no-verify)
    verify=0
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown option: $1" >&2
    usage >&2
    exit 1
    ;;
  esac
done

mkdir -p "$(dirname "$keyfile")"
chmod 700 "$(dirname "$keyfile")" 2>/dev/null || true

if [ -e "$keyfile" ] || [ -e "${keyfile}.pub" ]; then
  echo "Key already exists at ${keyfile}[.pub]." >&2
  echo "Pick another path with -f, or remove the existing key first." >&2
  exit 1
fi

opts=()
[ "$resident" -eq 1 ] && opts+=(-O resident)
[ "$verify" -eq 1 ] && opts+=(-O verify-required)

echo ">> Enrolling FIDO2/YubiKey SSH key (${keytype})"
echo ">> Touch the token when it blinks; enter its FIDO2 PIN if prompted."
echo

# -N '' : the on-disk private file is only a handle; the secret never leaves the token.
if ! ssh-keygen -t "$keytype" "${opts[@]}" -C "$comment" -f "$keyfile" -N ''; then
  echo >&2
  echo "Enrolment failed. Common causes:" >&2
  echo "  - no FIDO2 token present, or it needs a PIN set (ykman fido access change-pin)" >&2
  echo "  - token firmware predates ed25519-sk; retry with --ecdsa" >&2
  exit 1
fi

pub="$(cat "${keyfile}.pub")"

cat <<EOF

============================================================================
YubiKey SSH key enrolled.

  private handle : ${keyfile}       (useless without the physical token)
  public key     : ${keyfile}.pub

Public key - paste this into your release target's config:

${pub}

e.g. in the target's globalConfig:

  ghaf.global-config.security.ssh.release = {
    enable = true;
    authorizedKeys = [
      "${pub}"
    ];
  };

Then rebuild/flash the release image and connect through the net-vm jump:

  ssh -J ghaf@<device-ip> ghaf@gui-vm       # touch the YubiKey when it blinks

The default posture requires a token touch per login (verify-required), matching
ghaf.security.ssh.release.authorizedKeysOptions.
============================================================================
EOF
