# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
_: [

  # 40-local.rules
  ## Put your own watches after this point
  # -a exit,always -F arch=b64 -F path=file -F perm=rwxa -F key=text
  # -a exit,always -F arch=b64 -F dir=directory -F perm=rwxa -F key=text

  #find /bin -type f -perm -04000 2>/dev/null | awk '{ printf "-a always,exit -F arch=b64 -F path=%s -F perm=x -F auid>=1000 -F auid!=unset -F key=privileged\n", $1 }' > priv.rules
  #find /sbin -type f -perm -04000 2>/dev/null | awk '{ printf "-a always,exit -F arch=b64 -F path=%s -F perm=x -F auid>=1000 -F auid!=unset -F key=privileged\n", $1 }' >> priv.rules
  #find /usr/bin -type f -perm -04000 2>/dev/null | awk '{ printf "-a always,exit -F arch=b64 -F path=%s -F perm=x -F auid>=1000 -F auid!=unset -F key=privileged\n", $1 }' >> priv.rules
  #find /usr/sbin -type f -perm -04000 2>/dev/null | awk '{ printf "-a always,exit -F arch=b64 -F path=%s -F perm=x -F auid>=1000 -F auid!=unset -F key=privileged\n", $1 }' >> priv.rules
  #filecap /bin 2>/dev/null | sed '1d' | awk '{ printf "-a always,exit -F path=%s -F arch=b64 -F perm=x -F auid>=1000 -F auid!=unset -F key=privileged\n", $2 }' >> priv.rules
  #filecap /sbin 2>/dev/null | sed '1d' | awk '{ printf "-a always,exit -F path=%s -F arch=b64 -F perm=x -F auid>=1000 -F auid!=unset -F key=privileged\n", $2 }' >> priv.rules
  #filecap /usr/bin 2>/dev/null | sed '1d' | awk '{ printf "-a always,exit -F arch=b64 -F path=%s -F perm=x -F auid>=1000 -F auid!=unset -F key=privileged\n", $2 }' >> priv.rules
  #filecap /usr/sbin 2>/dev/null | sed '1d' | awk '{ printf "-a always,exit -F arch=b64 -F path=%s -F perm=x -F auid>=1000 -F auid!=unset -F key=privileged\n", $2 }' >> priv.rules
]
