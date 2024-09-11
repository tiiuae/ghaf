# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ final, prev }:
prev.cups.overrideAttrs (
  _final: _prev: {
    # Due to the incorrect printer URI bug: https://github.com/OpenPrinting/cups/issues/998
    src = final.fetchFromGitHub {
      owner = "OpenPrinting";
      repo = "cups";
      rev = "313c388dbc023bbcb75d1efed800d0cfc992a6cc";
      hash = "sha256-weu12hlrYUYY90pe0dJ6CiLtm8ynrLA9nT4j7iRwA+Q=";
    };
  }
)
