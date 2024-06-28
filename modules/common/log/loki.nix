# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  ...
}: let
  loki_data_dir = "/var/lib/loki";
  cfg = config.ghaf.logging.client;
in {
  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /var/lib/loki 0777 loki loki - -"
    ];

    services.loki = {
      inherit (config.ghaf.logging.client) enable;
      configuration = {
        auth_enabled = false;
        server = {
          http_listen_port = 3100;
          log_level = "warn";
        };

        common = {
          path_prefix = loki_data_dir;
          storage.filesystem = {
            chunks_directory = "${loki_data_dir}/chunks";
            rules_directory = "${loki_data_dir}/rules";
          };
          replication_factor = 1;
          ring.kvstore.store = "inmemory";
          ring.instance_addr = "127.0.0.1";
        };

        schema_config.configs = [
          {
            from = "2020-11-08";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index.prefix = "index_";
            index.period = "24h";
          }
        ];

        ruler = {
          alertmanager_url = "http://localhost:9093";
        };

        query_range.cache_results = true;
      };
    };

    networking.firewall.allowedTCPPorts = [config.ghaf.logging.port config.ghaf.logging.listener.port];

    systemd.services.loki.serviceConfig.after = ["alloy.service"];
  };
}
