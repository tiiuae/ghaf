# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
(_final: prev: {
  # https://github.com/NixOS/nixpkgs/issues/109280#issuecomment-973636212
  makeModulesClosure = x:
    prev.makeModulesClosure (x // {allowMissing = true;});
})
