# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This module provides backward compatibility for the authorizedSshKeys option.
# SSH keys are now configured via deployment profiles:
#   ghaf.reference.deployments.development.authorizedSshKeys
{ lib, ... }:
{
  options.ghaf.reference.personalize.keys = {
    authorizedSshKeys = lib.mkOption {
      description = ''
        List of authorized SSH keys.
        This option now reads from deployment profiles.
        Configure keys via: ghaf.reference.deployments.development.authorizedSshKeys
      '';
      type = lib.types.listOf lib.types.str;
      default = [ ];
      defaultText = lib.literalExpression "[]";
    };
  };
}
