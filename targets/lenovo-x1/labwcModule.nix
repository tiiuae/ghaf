# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Module for enabling LabWC
#
{
  ghaf.virtualization.microvm.guivm.extraModules = [
    {
      ghaf.profiles.graphics.compositor = "labwc";
    }
  ];
}
