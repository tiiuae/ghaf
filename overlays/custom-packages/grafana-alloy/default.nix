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
  patchPhase = (oldAttrs.patchPhase or "") + ''
    substituteInPlace internal/component/common/loki/wal/watcher.go \
      --replace-fail 'if r > index {' 'if r >= index {'
    substituteInPlace internal/component/common/loki/wal/watcher_test.go \
      --replace-fail \
        'return writeTo.ReadEntries.Length() == 6 // wait for watcher to catch up with both segments' \
        'return writeTo.ReadEntries.Length() == 7 // replay the marked segment and catch up with both later segments'
    substituteInPlace internal/component/common/loki/client/shards.go \
      --replace-fail \
        'defer batch.reportAsSentData(s.markerHandler, obs)' \
        $'batchHandled := true\n\tdefer func() {\n\t\tif batchHandled {\n\t\t\tbatch.reportAsSentData(s.markerHandler, obs)\n\t\t}\n\t}()' \
      --replace-fail \
        $'\tlevel.Error(s.logger).Log("msg", "final error sending batch, no retries left, dropping data"' \
        $'\tbatchHandled = s.ctx.Err() == nil\n\n\tlevel.Error(s.logger).Log("msg", "final error sending batch, no retries left, dropping data"'
  '';

  tags = builtins.filter (t: t != "gore2regex") oldAttrs.tags;
})
