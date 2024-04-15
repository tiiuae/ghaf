# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs ? import <nixpkgs> {} }:
let
  scriptPath = pkgs.concatTextFile {
    name = "gpio-test-script";
    files = [ "./simple-chardev-test.sh" ];
    executable = true;
    destination = "/bin/gpio-test-script";
  };
  gpioScript = scriptPath;
  gpiotestService = {
    description = "A simple service to test gpio pins";
    enable = true;
    executeAs = "root";
    startPrecondition = [ "networking" ];
    startCommand = "bash ${gpioScript}";
    restart = {
      failuresBeforeAction = 3;
      delaySec = 5;
    };
  };
in
{
  services.gpiotest = {
  description = "A simple service to test gpio pins";
  enable = true;
  executeAs = "root";
  startPrecondition = [ "networking" ];
  startCommand = "bash ${gpioScript}";
  restart = {
    failuresBeforeAction = 3;
    delaySec = 5;
  };
}

