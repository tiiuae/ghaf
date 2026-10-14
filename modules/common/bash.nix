# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, ... }:
{
  _file = ./bash.nix;

  programs.bash = {
    interactiveShellInit = ''
      export HISTCONTROL=erasedups:ignorespace
      export HISTSIZE=10000
      export HISTFILESIZE=20000
      export HISTTIMEFORMAT='%F %T '
      shopt -s histappend checkwinsize cmdhist
    '';
    promptInit = ''
      if [ "$TERM" != "dumb" ] || [ -n "$INSIDE_EMACS" ]; then
        PS1='\[\e[1;32m\]\u@${config.networking.hostName}\[\e[0m\]''${GHAF_HOSTNAME:+[\[\e[1;33m\]$GHAF_HOSTNAME\[\e[0m\]]}:\[\e[1;34m\]\w\[\e[0m\]\$ '
      else
        PS1='\u@${config.networking.hostName}''${GHAF_HOSTNAME:+[$GHAF_HOSTNAME]}:\w\$ '
      fi
    '';
  };
}
