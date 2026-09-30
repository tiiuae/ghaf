# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
import pathlib
import ssl
import struct
import sys
import uuid


def verify(directory, name):
    auth = (directory / f"{name}.auth").read_bytes()
    certificate = ssl.PEM_cert_to_DER_cert((directory / f"{name}.crt").read_text())
    length, revision, kind = struct.unpack_from("<IHH", auth, 16)
    if (
        length <= 24
        or 16 + length >= len(auth)
        or revision != 0x200
        or kind != 0xEF1
        or auth[24:40] != uuid.UUID("4aafd29d-68df-49ee-8aa9-347d375665a7").bytes_le
    ):
        raise ValueError("invalid authentication header")
    payload = auth[16 + length :]
    size, header_size, signature_size = struct.unpack_from("<III", payload, 16)
    # Each enrollment payload must install only its declared certificate.
    if (
        payload[:16] != uuid.UUID("a5c059a1-94e4-4aa7-87b5-ab155c2bf072").bytes_le
        or header_size != 0
        or size != len(payload)
        or size != 28 + signature_size
        or signature_size != 16 + len(certificate)
        or payload[44:] != certificate
    ):
        raise ValueError("enrollment payload does not match certificate")


if len(sys.argv) != 2:
    sys.exit("Usage: ghaf-verify-enrollment KEY_DIRECTORY")
for name in ("PK", "KEK", "db"):
    try:
        verify(pathlib.Path(sys.argv[1]), name)
    except (OSError, ValueError, struct.error) as error:
        sys.exit(f"Invalid {name}.auth: {error}")
