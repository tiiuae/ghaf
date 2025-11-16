# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Hardened configuration for journal-fss-setup.service
# This service generates FSS (Forward Secure Sealing) keys for systemd-journald
#
{
  ProtectSystem = "strict";
  PrivateNetwork = true;
  NoNewPrivileges = true;
  ProtectKernelTunables = true;
  ProtectKernelModules = true;
  ProtectControlGroups = true;
  RestrictAddressFamilies = [ "none" ];
  RestrictNamespaces = true;
  LockPersonality = true;
  MemoryDenyWriteExecute = true;
  RestrictRealtime = true;
  RestrictSUIDSGID = true;
  PrivateMounts = true;
  SystemCallFilter = [ "@system-service" ];
  CapabilityBoundingSet = [ "" ];
  ProtectClock = true;
  ProtectHostname = true;
  ProcSubset = "pid";
  ProtectProc = "invisible";
  UMask = "0077";
}
