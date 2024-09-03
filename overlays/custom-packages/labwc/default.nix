# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay customizes labwc - see comments for details
#
{ prev }: prev.labwc.overrideAttrs { patches = [ ./labwc-colored-borders.patch ]; }
