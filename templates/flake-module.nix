# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  flake.templates = {
    # Module template
    ghaf-module = {
      path = ./modules;
      description = "A config to bootstrap a Ghaf compatible module";
    };

    # Boilerplate for a derived project that uses the Ghaf framework
    target-boilerplate = {
      path = ./boilerplate;
      description = "Some boilerplate code to get you started";
    };
  };
}
