# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Function to generate NVIDIA Jetson Orin flash script
{
  hostConfiguration,
}:
hostConfiguration.pkgs.nvidia-jetpack.flashScript
