# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# DevID Certificate Authority Module (admin-vm)
#
# Manages a self-signed CA for issuing TPM DevID certificates.
# The CA key lives on admin-vm's LUKS-encrypted storage (TPM-sealed).
#
# Workflow:
# 1. On first boot: generates self-signed CA (RSA-4096)
# 2. Publishes CA cert to /etc/common/spire/ca/ca.pem (virtiofs)
# 3. Watches for CSR files from system VMs
# 4. Signs each CSR, writes cert to /etc/common/spire/devid/certs/{vmName}.pem
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.security.spiffe.devidCa;

  inherit (cfg) caDir;
  inherit (cfg) csrDir;
  inherit (cfg) certDir;
  inherit (cfg) caPublishPath;

  spireDevidCaSetupApp = pkgs.writeShellApplication {
    name = "spire-devid-ca-setup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssl
    ];
    text = ''
      mkdir -p "${caDir}" "${csrDir}" "${certDir}"
      chmod 0700 "${caDir}"

      CA_KEY="${caDir}/ca.key"
      CA_CERT="${caDir}/ca.pem"

      if [ ! -f "$CA_KEY" ]; then
        echo "Generating DevID CA key pair..."
        openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 \
          -nodes -keyout "$CA_KEY" -out "$CA_CERT" \
          -subj "/CN=Ghaf DevID CA/O=Ghaf/OU=SPIRE"
        chmod 0600 "$CA_KEY"
        chmod 0644 "$CA_CERT"
        echo "DevID CA created at $CA_CERT"
      else
        echo "DevID CA already exists"
      fi

      # Publish CA cert to virtiofs for system VMs and SPIRE server
      mkdir -p "$(dirname "${caPublishPath}")"
      cp "$CA_CERT" "${caPublishPath}"
      chmod 0644 "${caPublishPath}"
      echo "Published CA cert to ${caPublishPath}"
    '';
  };

  spireDevidSignApp = pkgs.writeShellApplication {
    name = "spire-devid-sign";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssl
      pkgs.inotify-tools
    ];
    text = ''
      CA_KEY="${caDir}/ca.key"
      CA_CERT="${caDir}/ca.pem"

      if [ ! -f "$CA_KEY" ]; then
        echo "ERROR: CA key not found at $CA_KEY" >&2
        exit 1
      fi

      sign_csr() {
        local csr="$1"
        local base
        base="$(basename "$csr" .csr)"
        local out="${certDir}/''${base}.pem"

        if [ -f "$out" ]; then
          echo "Certificate already exists for $base, skipping"
          return
        fi

        echo "Signing CSR for $base..."
        openssl x509 -req -in "$csr" \
          -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
          -days 365 -sha256 \
          -out "$out"
        chmod 0644 "$out"
        echo "Signed certificate written to $out"
      }

      # Sign any existing CSRs first
      for csr in "${csrDir}"/*.csr; do
        [ -f "$csr" ] && sign_csr "$csr"
      done

      # Watch for new CSRs
      echo "Watching ${csrDir} for new CSRs..."
      inotifywait -m -e close_write -e moved_to "${csrDir}" --format '%f' | while read -r filename; do
        if [[ "$filename" == *.csr ]]; then
          sign_csr "${csrDir}/$filename"
        fi
      done
    '';
  };
in
{
  _file = ./devid-ca.nix;

  options.ghaf.security.spiffe.devidCa = {
    enable = lib.mkEnableOption "DevID Certificate Authority for SPIRE TPM attestation";

    caDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/spire/ca";
      description = "Directory for CA key and certificate (on encrypted storage)";
    };

    caPublishPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/common/spire/ca/ca.pem";
      description = "Path where CA cert is published (virtiofs, readable by VMs)";
    };

    csrDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/common/spire/devid/requests";
      description = "Directory where system VMs submit CSR files (virtiofs)";
    };

    certDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/common/spire/devid/certs";
      description = "Directory where signed DevID certs are placed (virtiofs)";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.spire-devid-ca = {
      description = "SPIRE DevID CA setup";
      wantedBy = [ "multi-user.target" ];
      before = [ "spire-server.service" ];
      after = [ "local-fs.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe spireDevidCaSetupApp;
      };
    };

    systemd.services.spire-devid-sign = {
      description = "SPIRE DevID CSR signer (watches for CSRs from system VMs)";
      wantedBy = [ "multi-user.target" ];
      after = [
        "spire-devid-ca.service"
        "local-fs.target"
      ];
      requires = [ "spire-devid-ca.service" ];

      serviceConfig = {
        ExecStart = lib.getExe spireDevidSignApp;
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
