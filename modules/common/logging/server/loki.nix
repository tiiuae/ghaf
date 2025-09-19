# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.logging;
  enableLoki = cfg.server && cfg.local.enable;
in
{
  config = lib.mkIf enableLoki {
    services.loki = {
      enable = true;
      configuration = {
        auth_enabled = false;

        server = {
          http_listen_address = cfg.local.listenAddress;
          http_listen_port = cfg.local.listenPort;
          grpc_listen_port = 9096;
          log_level = "info";
        };

        common = {
          path_prefix = cfg.local.dataDir;
          storage = {
            filesystem = {
              chunks_directory = "${cfg.local.dataDir}/chunks";
              rules_directory = "${cfg.local.dataDir}/rules";
            };
          };
          replication_factor = 1;
          ring = {
            instance_addr = cfg.local.listenAddress;
            kvstore.store = "inmemory";
          };
        };

        schema_config = {
          configs = [
            {
              from = "2024-01-01";
              store = "tsdb";
              object_store = "filesystem";
              schema = "v13";
              index = {
                prefix = "ghaf_logs_";
                period = "24h";
              };
            }
          ];
        };

        storage_config = {
          tsdb_shipper = {
            active_index_directory = "${cfg.local.dataDir}/tsdb-index";
            cache_location = "${cfg.local.dataDir}/tsdb-cache";
          };
          filesystem = {
            directory = "${cfg.local.dataDir}/chunks";
          };
        };

        # Compactor for retention
        compactor = lib.mkIf cfg.local.retention.enable {
          working_directory = "${cfg.local.dataDir}/compactor";
          compaction_interval = cfg.local.retention.compactionInterval;
          retention_enabled = true;
          retention_delete_delay = cfg.local.retention.deleteDelay;
          retention_delete_worker_count = 150;
          delete_request_store = "filesystem";
        };

        # Retention policies
        limits_config = lib.mkIf cfg.local.retention.enable {
          retention_period = cfg.local.retention.defaultPeriod;

          # Per-category retention
          retention_stream = lib.mapAttrsToList (category: period: {
            selector = ''{log_category="${category}"}'';
            priority = 1;
            inherit period;
          }) cfg.local.retention.categoryPeriods;
        };

        # Query cache
        query_range = {
          results_cache = {
            cache = {
              embedded_cache = {
                enabled = true;
                max_size_mb = 100;
              };
            };
          };
        };
      };
    };

    # Create data directories
    systemd.tmpfiles.rules = [
      "d ${cfg.local.dataDir} 0750 loki loki -"
      "d ${cfg.local.dataDir}/chunks 0750 loki loki -"
      "d ${cfg.local.dataDir}/tsdb-index 0750 loki loki -"
      "d ${cfg.local.dataDir}/tsdb-cache 0750 loki loki -"
      "d ${cfg.local.dataDir}/compactor 0750 loki loki -"
      "d ${cfg.local.dataDir}/rules 0750 loki loki -"
    ];
  };
}
