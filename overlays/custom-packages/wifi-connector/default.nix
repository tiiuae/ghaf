# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
(final: _prev: {
  wifi-connector = final.callPackage ../../../packages/wifi-connector {};
  wifi-connector-nmcli = final.callPackage ../../../packages/wifi-connector {useNmcli = true;};
})
