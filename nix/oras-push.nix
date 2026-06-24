# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  perSystem = { system, ... }: {
    apps.ota-oras-push = inputs.givc.apps.${system}.ota-oras-push;
  };
}
