#! /usr/bin/env bash
# shellcheck shell=bash
# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Notes:
#   Thi script can be used enroll finger print
set +xo pipefail
mainmenu () {
  echo "Please choose which finger you want to enroll"
  echo "0. Right Thumb"
  echo "1. Right Index Finger"
  echo "2. Right Middle Finger"
  echo "3. Right Ring Finger"
  echo "4. Right Little Finger"
  echo "5. Left Thumb"
  echo "6. Left Index Finger"
  echo "7. Left Middle Finger"
  echo "8. Left Ring Finger"
  echo "9. Left Little Finger"
  echo ""
}
readfunc()
{
  while true; do
  read  -r -n 1 -p "Input Selection:" mainmenuinput
  echo ""
  echo "Please tap on power button for finger enrollment"
  echo ""
  if [ "$mainmenuinput" = "0" ]; then
        fprintd-enroll -f right-thumb
  elif [ "$mainmenuinput" = "1" ]; then
        fprintd-enroll -f right-index-finger
  elif [ "$mainmenuinput" = "2" ]; then
        fprintd-enroll -f right-middle-finger
  elif [ "$mainmenuinput" = "3" ]; then
        fprintd-enroll -f right-ring-finger
  elif [ "$mainmenuinput" = "4" ]; then
        fprintd-enroll -f right-little-finger
  elif [ "$mainmenuinput" = "5" ];then
        fprintd-enroll -f left-thumb
  elif [ "$mainmenuinput" = "6" ];then
        fprintd-enroll -f left-index-finger
  elif [ "$mainmenuinput" = "7" ];then
        fprintd-enroll -f left-middle-finger
  elif [ "$mainmenuinput" = "8" ];then
        fprintd-enroll -f left-ring-finger
  elif [ "$mainmenuinput" = "9" ];then
        fprintd-enroll -f left-ring-finger
  else
        echo "Invalid Input"
            mainmenu
            readfunc
  fi
    echo ""
    exit 0
done
}
mainmenu
readfunc