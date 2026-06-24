# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Only ship with one voice per language
{ prev }:
prev.mbrola-voices.override {
  languages = [ "*1" ];
}
