# Copyright 2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Revert to older Firefox while cross-compiling, until the 120.0.1 version
# update patch hits 23.05 and/or 23.11
#
(_final: prev: {
  # Bug which prevent cross-compilation applied upstream, should be avaliable in 121 or 122
  # Temporary revert to firefox-esr (aka 115)
  firefox =
    if prev.firefox.version == "120.0"
    then prev.firefox-esr
    else prev.firefox;
})
