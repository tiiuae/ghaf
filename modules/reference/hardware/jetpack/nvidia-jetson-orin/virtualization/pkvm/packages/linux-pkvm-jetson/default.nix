# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Stable Linux 6.18 kernel with pKVM patches for arm64.
# The same kernel is used for both host and guests on pvm target, only with different defconfigs.
#
{
  nvidia-jetpack7,
  fetchFromGitHub,
  structuredExtraConfig ? { },
  argsOverride ? { },
  ...
}@args:
nvidia-jetpack7.kernel.override {
  inherit structuredExtraConfig;

  argsOverride =
    args
    // {
      pname = "linux-pkvm-jetson";
      version = "6.18.0";
      extraMeta.branch = "pkvm-v6.18-dev";

      src = fetchFromGitHub {
        owner = "tiiuae";
        repo = "linux-pkvm-jetson";
        rev = "635111311b0977bf463ffe1174bbd69041bde66f"; # pkvm-6.18-dev - 07-10-2026
        hash = "sha256-tF4oyAqWZ56mVUIY1sMQfaacw3ESmJ5Op6KHP+uhsZU=";
      };
    }
    // argsOverride;
}
