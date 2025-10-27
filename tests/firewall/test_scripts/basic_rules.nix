# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ nodes, pkgs, ... }:
''

  def count_entries_with_exact_flags(log_data, expected_flags, expected_count, expected_proto="TCP"):
    """
     Parses log_data and asserts that the number of entries containing
     exactly the expected_flags (no more, no less) equals expected_count.
    """
    if expected_proto.upper() == "TCP":
        pattern = re.compile(
            r"SRC=(?P<src>\S+) DST=(?P<dst>\S+) LEN=(?P<len>\d+) TOS=(?P<tos>\S+) PREC=(?P<prec>\S+) "
            r"TTL=(?P<ttl>\d+) ID=(?P<id>\d+).*?PROTO=(?P<proto>\S+) SPT=(?P<spt>\d+) DPT=(?P<dpt>\d+)"
            r"(?: WINDOW=(?P<window>\d+) RES=(?P<res>\S+)\s+"
            r"(?P<flags>(?:(?:\bACK\b|\bPSH\b|\bRST\b|\bSYN\b|\bFIN\b|\bURG\b|\bECE\b|\bCWR\b)(?:\s+(?:\bACK\b|\bPSH\b|\bRST\b|\bSYN\b|\bFIN\b|\bURG\b|\bECE\b|\bCWR\b))*)?))?"
        )
    elif expected_proto.upper() == "ICMP":
        # Adjust regex for ICMP - no ports, no TCP flags
        pattern = re.compile(
            r"SRC=(?P<src>\S+) DST=(?P<dst>\S+) LEN=(?P<len>\d+) TOS=(?P<tos>\S+) PREC=(?P<prec>\S+) "
            r"TTL=(?P<ttl>\d+) ID=(?P<id>\d+).*?PROTO=(?P<proto>ICMP)"
        )
    else:
        # Generic pattern or raise error for unsupported proto
        raise ValueError(f"Unsupported protocol: {expected_proto}")

    count = 0
    expected_set = set(expected_flags)

    for line in log_data.strip().split('\n'):
        match = pattern.search(line)
        if match:
            entry = match.groupdict()
            proto = entry.get("proto", "").upper()
            if proto != expected_proto.upper():
                continue

            if proto == "TCP":
                flags_raw = entry.get("flags", "").strip()
                flags = set(flags_raw.split()) if flags_raw else set()
                if flags == expected_set:
                    count += 1
            else:
                # For ICMP, no flags - just count matching protocol entries
                count += 1

    print(f"Found {count} entries with protocol {expected_proto} " +
          (f"and exactly flags {expected_flags}" if expected_proto.upper() == "TCP" else ""))
    assert count == expected_count, (
        f"Expected {expected_count} entries with protocol {expected_proto} " +
        (f"and exactly flags {expected_flags}, found {count}" if expected_proto.upper() == "TCP" else f", found {count}")
    )


  with subtest("Block packets with bogus TCP flags"):
     # Trigger custom traffic
     # Null scan
     externalVM.execute("sudo nmap -sN -p 80-84 ${(pkgs.lib.head nodes.netVM.networking.interfaces.eth1.ipv4.addresses).address}")
     # FIN + SYN
     externalVM.execute("sudo hping3 --faster -c 10 -p 80 -S -F ${(pkgs.lib.head nodes.netVM.networking.interfaces.eth1.ipv4.addresses).address}")
     # SYN + RST
     externalVM.execute("sudo hping3 --faster -c 10 -p 90 -S -R ${(pkgs.lib.head nodes.netVM.networking.interfaces.eth1.ipv4.addresses).address}")
     # FIN + RST
     externalVM.execute("sudo hping3 --faster -c 10 -p 100 -F -R ${(pkgs.lib.head nodes.netVM.networking.interfaces.eth1.ipv4.addresses).address}")
     # FIN
     externalVM.execute("sudo hping3 --faster -c 10 -p 110 -F ${(pkgs.lib.head nodes.netVM.networking.interfaces.eth1.ipv4.addresses).address}")
     # URG
     externalVM.execute("sudo hping3 --faster -c 10 -p 120 -U ${(pkgs.lib.head nodes.netVM.networking.interfaces.eth1.ipv4.addresses).address}")
     # PSH
     externalVM.execute("sudo hping3 --faster -c 10 -p 130 -P ${(pkgs.lib.head nodes.netVM.networking.interfaces.eth1.ipv4.addresses).address}")
     # ALL
     externalVM.execute("sudo hping3 --faster -c 10 -p 140 -FSRPAU ${(pkgs.lib.head nodes.netVM.networking.interfaces.eth1.ipv4.addresses).address}")
     # FIN + PSH + URG (XMAS)
     externalVM.execute("sudo hping3 --faster -c 10 -p 150 -FPU ${(pkgs.lib.head nodes.netVM.networking.interfaces.eth1.ipv4.addresses).address}")
     # FIN + PSH + URG + SYN
     externalVM.execute("sudo hping3 --faster -c 10 -p 160 -FPUS ${(pkgs.lib.head nodes.netVM.networking.interfaces.eth1.ipv4.addresses).address}")
     # FIN + URG + SYN + RST + ACK
     externalVM.execute("sudo hping3 --faster -c 10 -p 170 -FUSRA ${(pkgs.lib.head nodes.netVM.networking.interfaces.eth1.ipv4.addresses).address}")
     netVM.sleep(2)

     # Extract mangle-drop logs
     mangle_drop_log = netVM.execute("sudo journalctl | grep -E 'ghaf-fw-mangle-drop:'")

     # NULL SCAN
     count_entries_with_exact_flags(mangle_drop_log[1], expected_flags=[], expected_count=5*2)
     # FIN + SYN
     count_entries_with_exact_flags(mangle_drop_log[1], expected_flags=["FIN", "SYN"], expected_count=10)
     # SYN + RST
     count_entries_with_exact_flags(mangle_drop_log[1], expected_flags=["RST", "SYN"], expected_count=10)
     # FIN + RST
     count_entries_with_exact_flags(mangle_drop_log[1], expected_flags=["RST", "FIN"], expected_count=10)
     # FIN
     count_entries_with_exact_flags(mangle_drop_log[1], expected_flags=["FIN"], expected_count=10)
     # URG
     count_entries_with_exact_flags(mangle_drop_log[1], expected_flags=["URG"], expected_count=10)
     # PSH
     count_entries_with_exact_flags(mangle_drop_log[1], expected_flags=["PSH"], expected_count=10)
     # ALL
     count_entries_with_exact_flags(mangle_drop_log[1], expected_flags=["PSH","FIN","RST","ACK","SYN","URG"], expected_count=10)
     # FIN + PSH + URG (XMAS)
     count_entries_with_exact_flags(mangle_drop_log[1], expected_flags=["PSH","FIN","URG"], expected_count=10)
     # FIN + PSH + URG + SYN
     count_entries_with_exact_flags(mangle_drop_log[1], expected_flags=["PSH","FIN","URG","SYN"], expected_count=10)
     # FIN + URG + SYN + RST + ACK
     count_entries_with_exact_flags(mangle_drop_log[1], expected_flags=["FIN","URG","SYN","RST","ACK"], expected_count=10)

  with subtest("INPUT rules"):
    # Loopback test
    netVM.succeed("ping -c 5 -I lo 127.0.0.1")

    # icmp test
    num_icmp_packets =20
    num_firewall_burst_allow = 5
    externalVM.succeed(f"ping -c {num_icmp_packets} ${(pkgs.lib.head nodes.netVM.networking.interfaces.eth1.ipv4.addresses).address}")
    # Extract filter-drop logs
    filter_drop_log = netVM.execute("sudo journalctl | grep -E 'ghaf-fw-filter-drop:'")
    count_entries_with_exact_flags(filter_drop_log[1], expected_flags = [""], expected_count=num_icmp_packets-num_firewall_burst_allow, expected_proto="ICMP")


''
