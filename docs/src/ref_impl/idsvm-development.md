<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# IDS VM Further Development


## Implementation

The [IDS VM](../architecture/adr/idsvm.md) is implemented as a regular Micro VM with static IP.

The [mitmproxy](https://mitmproxy.org/) is included in the demonstrative interactive proxy to enable analysis of TLS-protected data on the fly. Also, [Snort](https://snort.org/) network intrusion detection and prevention system package is included but no dedicated UI nor proper utilization is provided.

Enforcing network traffic to go through IDS VM is crucial to the IDS VM functionality. It is achieved by setting the IDS VM to be the gateway of other VMs in [dnsmasq](https://thekelleys.org.uk/dnsmasq/doc.html) configuration of Net VM. There is a risk that one could change the gateway settings of the VM to bypass the IDS VM. This however requires root (sudo) rights and it is assumed here that these rights are enabled only in the debug build.


## mitmproxy

[**mitmproxy**](https://mitmproxy.org/) is a free and open-source interactive HTTPS proxy. It is your Swiss Army Knife for debugging, testing, privacy measurements, and penetration testing. It can be used to intercept, inspect, modify and replay web traffic such as HTTP/1, HTTP/2, WebSockets, or any other SSL/TLS-protected protocols.

In IDS VM, we use **mitmweb**[^note1] tool to demonstrate mitmproxy's capabilities. It provides a web-based user interface that allows interactive examination and modification of HTTP(s) traffic. The mtmproxy package also includes a console tool that provides the same functionalities in a text-based interface and a command-line tool **mitmdump** to view, record, and programmatically transform HTTP(s) traffic.

The mitmweb tool is run in *ids-vm* as a systemd service. It starts automatically when *ids-vm* boots up. The UI it provides is accessible at <http://localhost:8081>, so it is available from *ids-vm* only. However, with SSH port forwarding it is possible to access the UI from other VMs. To that purpose, GUI VM has a script *mitmweb-ui* that creates an SSH tunnel between *ids-vm* and *chromium-vm*, launches Chromium, and connects to the UI address.


## Certificates

mitmproxy can decrypt encrypted traffic on the fly, as long as the client trusts mitmproxy's built-in certificate authority (CA). CA certificates are the same for all *ids-vm* instances, as they are hardcoded to the IDS VM implementation. In the release version, these should be randomly generated and stored securely.

By default, any of the clients should not trust mitmproxy's CA. These CA certificates should be installed in the OS's CA storage. However, many client applications (web browsers, for example) use their own CA bundles, and importing custom certificates there can be complicated or require manual user interaction. In our case, this difficulty is circumvented in *chromium-vm* by disabling certificate verification errors, if the certificate chain contains a certificate which SPKI fingerprint matches that of mitmproxy's CA certificate fingerprint. This does not degrade server verification security since mitmproxy validates upstream certificates using a certified Python package which provides Mozilla's CA Bundle.

Some applications use certificate pinning to prevent man-in-the-middle attacks. As a consequence mitmproxy's certificates will not be accepted by these applications without patching applications manually. Other option is to set mitmproxy to use ignore_hosts option to prevent mitmproxy from intercepting traffic to these specific domains.


[^note1]: **mitmproxy** is an interactive, SSL/TLS-capable intercepting proxy with a console interface for HTTP/1, HTTP/2, and WebSockets. **mitmweb** is a web-based interface for mitmproxy. **mitmdump** is the command-line version of mitmproxy. Source: [mitmproxy docs](https://docs.mitmproxy.org/stable/#3-powerful-core-tools).
