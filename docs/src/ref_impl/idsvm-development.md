<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# idsvm Further Development

## Implementation

The idsvm is implemented as a regular microVM with static IP.
The mitmproxy is included to demonstrative interactive proxy to enable analysis of TLS protected data on the fly. Also Snort network intrusion detection and prevention system package is included, but no dedicated UI nor proper utilization is provided.

Enforcing network traffic to go through idsvm is crucial part of the idsvm functionality.
It is achieved by setting the idsvm to be the gateway of other VMs in dnsmasq configuration
of netvm. There is a risk is that one could change gateway settings of the VM to bypass the idsvm. This however requires root (sudo) rights and it is assumed here that these rights are enabled only in debug build.

## mitmproxy

"The mitmproxy is a free and open source interactive HTTPS proxy. It is your swiss-army knife for debugging, testing, privacy measurements, and penetration testing. It can be used to intercept, inspect, modify and replay web traffic such as HTTP/1, HTTP/2, WebSockets, or any other SSL/TLS-protected protocols."
https://mitmproxy.org/

In idsvm we use mitmweb tool to demonstrate mitmproxy's capabilities. It provides web-based user interface that allows interactive examination and modification of HTTP(s) traffic.
Mitmproxy package also includes console tool that provides basically same functionalities in text-based interface and it also includes a command-line tool mitmdump to view, record, and programmatically transform HTTP(s) traffic.

Mitmweb tool is run in idsvm as a systemd service. It starts automatically when idsvm boots up.
The UI it provides is accessible in the web address http://localhost:8081 so basically it is available from idsvm only. However using SSH portforwarfing it is possible to access the UI from other VMs. To that purpose the guivm has a script called mitmweb-ui. It creates a SSH tunnel between idsvm and chromium-vm, launches the Chromium and connects to the UI-address.

## Certificates

Mitmproxy can decrypt encrypted traffic on the fly, as long as the client trusts mitmproxy's built-in certificate authority (CA). CA certificates are in hardcoded to the idsvm implementation which means they are same for all idsvm instances. In release version these should be randomly generated and stored securely.

By default any of the clients should not trust mitmproxy's CA. That is why these CA certicates should be installed to OS's CA storage. However many client applications (web browsers) use their own CA bundles and importing custom certificates to there can be very complicated or requires manual user interaction. In our case this difficulty is circumvented in chromium-vm by disabling certicate verification errors, if the certicate chain contains a certificate which SPKI fingerprint matches that of mitmproxy's CA certificate fingerprint. This does not degrade security of server verification since mitmproxy itself validates upstream certificates using certifi Python package, which provides Mozilla's CA Bundle.

Some applications use certificate pinning to prevent man-in-the-middle attacks. As a consequence mitmproxy's certificates will not be accepted by these applications without patching applications manually. Other option is to set mitmproxy to use ignore_hosts option to prevent mitmproxy from intercepting traffic to these specific domains.
