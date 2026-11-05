# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# How deep client-side Suricata rules look into a flow: DNS whole, TLS and QUIC
# only the handshake, plaintext HTTP and SMTP into bodies and attachments.
[
  {
    proto = "udp";
    port = 53;
  }
  {
    proto = "tcp";
    port = 53;
  }
  {
    proto = "tcp";
    port = 443;
    packets = 10;
  }
  {
    proto = "tcp";
    port = 8443;
    packets = 10;
  }
  {
    proto = "udp";
    port = 443;
    packets = 6;
  }
  {
    proto = "tcp";
    port = 80;
    bytes = 1048576;
  }
  {
    proto = "tcp";
    port = 8080;
    bytes = 1048576;
  }
  {
    proto = "tcp";
    port = 25;
    bytes = 1048576;
  }
  {
    proto = "tcp";
    port = 465;
    bytes = 1048576;
  }
  {
    proto = "tcp";
    port = 587;
    bytes = 1048576;
  }
]
