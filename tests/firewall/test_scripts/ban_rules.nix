# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ nodes, pkgs, ... }:
let
  externalVmIp = (pkgs.lib.head nodes.externalVM.networking.interfaces.eth1.ipv4.addresses).address;
  netVmIp = (pkgs.lib.head nodes.netVM.networking.interfaces.eth1.ipv4.addresses).address;
in
''
  from collections import Counter

  pattern = re.compile(
      r'(Blacklist \[add\]:|Packet \[ban\]:).*SRC=(\d+\.\d+\.\d+\.\d+).*DST=(\d+\.\d+\.\d+\.\d+)'
  )

  def parse_and_count(log_text):
      counts = Counter()
      for line in log_text.splitlines():
          match = pattern.search(line)
          if match:
              log_type, src, dst = match.groups()
              counts[(log_type, src, dst)] += 1
      return counts

  # List of source IPs to simulate attacks from
  source_ips = ["192.168.1.50", "192.168.1.30", "192.168.1.40","${externalVmIp}"]
  # Run hping3 from each source IP
  for src_ip in source_ips:
    # Send traffic with spoofed source IP
    externalVM.execute(
        f"sudo hping3 -S -p 22 -i u10000 -c 20 -a {src_ip} ${netVmIp}"
    )
  log_output = netVM.execute("sudo journalctl | grep -E 'Blacklist \\[add\\]:|Packet \\[ban\\]:'")
  results = parse_and_count(log_output[1])
  for (log_type, src, dst), count in results.items():
    print(f"{log_type} SRC={src} DST={dst} → {count} times")

  # Assertions to check expected results
  assert results[("Blacklist [add]:", "${externalVmIp}", "${netVmIp}")] == 1, "Blacklist [add] count mismatch"

  assert results[("Packet [ban]:", "${externalVmIp}", "${netVmIp}")] == 1, "Packet [ban] count mismatch"


  ipset_ret = netVM.execute("sudo ipset list");
  print(f"IPSET: {ipset_ret[0]}, {ipset_ret[1]}");

  # Extract only the IP addresses from the Members section
  blacklisted_ips = [
    line.split()[0] for line in ipset_ret[1].splitlines()
    if re.match(r"\d+\.\d+\.\d+\.\d+", line)
  ]

  print("Blacklisted IPs:", blacklisted_ips)
  for ip in source_ips:
    assert ip in blacklisted_ips, f"{ip} not found in BLACKLIST ipset!"

''
