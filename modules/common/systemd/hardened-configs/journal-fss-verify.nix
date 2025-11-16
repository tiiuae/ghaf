# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Hardened configuration for journal-fss-verify.service
# This service verifies journal integrity using Forward Secure Sealing
#
{
  ProtectSystem = "full";
  PrivateNetwork = true;
  NoNewPrivileges = true;
  ProtectKernelTunables = true;
  ProtectKernelModules = true;
  ProtectControlGroups = true;
  RestrictAddressFamilies = [ "AF_UNIX" ]; # Needs AF_UNIX for systemd-cat
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
