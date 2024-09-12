# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay applies some scss customisations. This is set as an overlay as
# the scss files need to be compiled.
#
{ prev }:
prev.swaynotificationcenter.overrideAttrs { patches = [ ./0001-Set-ghaf-color-theme.patch ]; }
