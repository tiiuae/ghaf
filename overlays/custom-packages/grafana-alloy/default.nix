# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Drop the gore2regex build tag so loki.secretfilter uses stdlib regexp instead of
# go-re2 library, which requires mmap(PROT_EXEC) and is incompatible with
# MemoryDenyWriteExecute=true set in our alloy service hardening.
# This change ensures we don't sacrifice security for performance
# Ref:
# https://github.com/grafana/alloy/blob/63ab53d8b477a0403ce24dbd759572707bd3fef2/Makefile#L131
{ prev }:
prev.grafana-alloy.overrideAttrs (oldAttrs: {
  tags = builtins.filter (t: t != "gore2regex") oldAttrs.tags;
})
