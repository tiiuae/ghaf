# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{pkgs, ...}: let
  server-ip-port = "192.168.101.66:3100";
in {
  environment.etc."promtail-local-config.yaml".text = ''
    server:
      http_listen_port: 9101
      grpc_listen_port: 0

    positions:
      filename: /tmp/positions.yaml

    client:
      url: http://${server-ip-port}/loki/api/v1/push

    scrape_configs:
      - job_name: journal
        journal:
          path: /var/log/journal
          labels:
            job: systemd-journal
        relabel_configs:
          - source_labels: ['__journal__systemd_unit']
            target_label: 'unit'
  '';

  systemd.services.promtail = {
    description = "Service to upload journal logs";
    enable = true;
    after = ["network-online.target"];
    serviceConfig = {
      ExecStart = "${pkgs.grafana-loki}/bin/promtail -config.file=/etc/promtail-local-config.yaml";
      Restart = "on-failure";
      RestartSec = "1";
    };
    wantedBy = ["multi-user.target"];
  };
}
