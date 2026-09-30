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
        rev = "e83d6b0ace88a641bef50dafd27f7d8c55726b75"; # pkvm-6.18-dev - 25-09-2026
        hash = "sha256-M6DhjF1s2ruyBqeMzfl588tj+UCeUhqJa6Chtp273BU=";
      };
    }
    // argsOverride;
}
