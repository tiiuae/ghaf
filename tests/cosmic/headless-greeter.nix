# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  callPackage,
  runCommand,
  bash,
  formats,
  greetd,
}:
let
  waiter = callPackage ../../modules/desktop/graphics/cosmic/wait-for-display.nix { };
  greeterConfig =
    (formats.toml { }).generate "greetd.toml"
      self.nixosConfigurations.intel-laptop-debug.config.microvm.vms.gui-vm.evaluatedConfig.config.services.greetd.settings;
in
runCommand "cosmic-headless-greeter" { } ''
  # The invalid VT stops greetd after parsing the generated config, before opening a terminal.
  if ${greetd}/bin/greetd --config ${greeterConfig} --vt invalid > parser.log 2>&1; then
    exit 1
  fi
  cat parser.log
  grep -F "could not parse vt number" parser.log

  start_waiter() {
    timeout 20 ${waiter}/bin/wait-for-display "$PWD/drm" \
      ${bash}/bin/bash -c 'printf "%s" "$1" > "$2"' _ "argument with spaces" "$PWD/started" &
    pid=$!
  }
  assert_waiting() {
    sleep 2
    kill -0 "$pid"
    test ! -e started
  }
  trap 'kill "$pid" 2>/dev/null || true' EXIT

  start_waiter
  assert_waiting

  mkdir -p drm/card0-DP-1
  echo disconnected > drm/card0-DP-1/status
  echo 1920x1080 > drm/card0-DP-1/modes
  assert_waiting

  : > drm/card0-DP-1/modes
  echo connected > drm/card0-DP-1/status
  assert_waiting

  mkdir -p drm/card1-HDMI-A-1
  echo 1280x720 > drm/card1-HDMI-A-1/modes
  echo connected > drm/card1-HDMI-A-1/status
  wait "$pid"
  test "$(cat started)" = "argument with spaces"

  rm started
  start_waiter
  wait "$pid"
  test -e started

  rm -r drm started
  start_waiter
  assert_waiting
  kill "$pid"
  if wait "$pid"; then exit 1; fi
  test ! -e started
  trap - EXIT
  touch "$out"
''
