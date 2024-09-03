# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay will apply gtklock patches which are merged in master branch
# https://github.com/jovanlanik/gtklock/commit/d22127f0fd61bbeba8c12378b3c5b46cc3064d63
# https://github.com/jovanlanik/gtklock/commit/e0e7f6d5ae7667fcc3479b6732046c67275b2f2f
# TODO: Remove patches, once there new release for gtlk-lock
#
{ prev }:
prev.gtklock.overrideAttrs {
  patches = [
    ./auth-guard-against-race-condition-with-messages.patch
    ./update.patch
  ];
}
