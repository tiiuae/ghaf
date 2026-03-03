# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# DevID Key Provisioning Module (system VMs with hardware TPM)
#
# On each system VM with TPM passthrough, this service:
# 1. Creates an ephemeral TPM primary key
# 2. Creates RSA-2048 signing key under it
# 3. Saves key blobs to encrypted storage
# 4. Generates a CSR
# 5. Submits CSR to admin-vm via virtiofs
# 6. Waits for signed certificate
#
# Key blobs are transient (no persistent TPM handles needed).
# The SPIRE agent loads key blobs on demand.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.security.spiffe.devidProvision;

  spireDevidProvisionApp = pkgs.writeShellApplication {
    name = "spire-devid-provision";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.tpm2-tools
      pkgs.openssl
    ];
    text = ''
      VM_NAME="${cfg.vmName}"
      DEVID_DIR="${cfg.devidDir}"
      CSR_DIR="${cfg.csrDir}"
      CERT_DIR="${cfg.certDir}"
      mkdir -p /run/tpm

      # Provision through TPM resource manager device.
      export TPM2TOOLS_TCTI="device:/dev/tpmrm0"

      mkdir -p "$DEVID_DIR"
      chmod 0750 "$DEVID_DIR"
      chown root:spire "$DEVID_DIR"

      PRIV_BLOB="$DEVID_DIR/devid.priv"
      PUB_BLOB="$DEVID_DIR/devid.pub"
      PUB_PEM="$DEVID_DIR/devid-pub.pem"
      CERT_FILE="$DEVID_DIR/devid.pem"
      SHARED_CERT_FILE="$CERT_DIR/$VM_NAME.pem"
      TSS_PUB_BLOB="$DEVID_DIR/devid.tss.pub"
      PUB_REQ_FILE="$CSR_DIR/$VM_NAME.pub.pem"

      cleanup_contexts() {
        if [ -f "$DEVID_DIR/devid.ctx" ]; then
          timeout 5 tpm2_flushcontext "$DEVID_DIR/devid.ctx" -Q >/dev/null 2>&1 || true
        fi
        if [ -f "$DEVID_DIR/primary.ctx" ]; then
          timeout 5 tpm2_flushcontext "$DEVID_DIR/primary.ctx" -Q >/dev/null 2>&1 || true
        fi
        rm -f "$DEVID_DIR/primary.ctx" "$DEVID_DIR/devid.ctx" "$TSS_PUB_BLOB"
      }

      clear_devid_material() {
        cleanup_contexts
        rm -f "$PRIV_BLOB" "$PUB_BLOB" "$PUB_PEM" "$CERT_FILE" "$TSS_PUB_BLOB"
      }

      normalize_private_blob() {
        if [ ! -f "$PRIV_BLOB" ]; then
          return
        fi

        local priv_size priv_prefix_hex priv_prefix
        priv_size=$(wc -c < "$PRIV_BLOB")
        priv_prefix_hex=$(od -An -tx1 -N2 "$PRIV_BLOB" 2>/dev/null | tr -d ' \n')

        if [[ "$priv_prefix_hex" =~ ^[0-9a-fA-F]{4}$ ]] && [ "$priv_size" -gt 2 ]; then
          priv_prefix=$((16#$priv_prefix_hex))
        else
          priv_prefix=""
        fi

        if [ -n "$priv_prefix" ] && [ $((priv_prefix + 2)) -eq "$priv_size" ]; then
          echo "Converting DevID private blob from TPM2B_PRIVATE to TPM2_PRIVATE"
          if ! dd if="$PRIV_BLOB" of="$PRIV_BLOB.raw" bs=1 skip=2 status=none 2>/dev/null; then
            echo "Failed to normalize DevID private blob"
            echo "Falling back to join_token attestation"
            echo "normalize-private-failed" > /run/tpm/devid-status 2>/dev/null || true
            rm -f "$PRIV_BLOB.raw"
            exit 0
          fi
          mv -f "$PRIV_BLOB.raw" "$PRIV_BLOB"
        fi
      }

      create_srk_primary() {
        # Match SPIRE/go-tpm SRKTemplateHighRSA as closely as possible.
        # Fallback keeps compatibility with older tpm2-tools variants.
        if timeout 15 tpm2_createprimary -C owner \
          -G rsa2048:null:aes128cfb \
          -a "fixedtpm|fixedparent|sensitivedataorigin|userwithauth|restricted|decrypt|noda" \
          -c "$DEVID_DIR/primary.ctx" -Q 2>/dev/null; then
          return 0
        fi

        timeout 15 tpm2_createprimary -C owner -c "$DEVID_DIR/primary.ctx" -Q 2>/dev/null
      }

      wait_for_tpm_ready() {
        for attempt in $(seq 1 30); do
          if timeout 5 tpm2_getcap properties-fixed >/dev/null 2>&1; then
            return 0
          fi
          echo "Waiting for TPM readiness... ($attempt/30)"
          sleep 2
        done
        return 1
      }

      load_existing_devid_key() {
        cleanup_contexts

        if ! create_srk_primary; then
          return 1
        fi

        if ! timeout 15 tpm2_load \
          -C "$DEVID_DIR/primary.ctx" \
          -u "$PUB_BLOB" \
          -r "$PRIV_BLOB" \
          -c "$DEVID_DIR/devid.ctx" -Q 2>/dev/null; then
          cleanup_contexts
          return 1
        fi

        return 0
      }

      rebuild_missing_public_artifacts() {
        if [ -s "$PUB_PEM" ]; then
          return 0
        fi

        echo "WARNING: DevID public PEM missing, rebuilding from key blobs"
        if ! load_existing_devid_key; then
          echo "WARNING: Failed to load existing DevID key blobs"
          return 1
        fi

        if ! tpm2_readpublic -c "$DEVID_DIR/devid.ctx" -f pem -o "$PUB_PEM" -Q 2>/dev/null; then
          cleanup_contexts
          echo "WARNING: Failed to rebuild DevID public PEM"
          return 1
        fi

        chown root:spire "$PUB_PEM"
        chmod 0640 "$PUB_PEM"
        cleanup_contexts
        return 0
      }

      cert_matches_pub() {
        local cert_file="$1"
        local pub_file="$2"
        local cert_pub=""
        local req_pub=""

        if [ ! -s "$cert_file" ] || [ ! -s "$pub_file" ]; then
          return 1
        fi

        cert_pub=$(mktemp)
        req_pub=$(mktemp)

        if ! openssl x509 -in "$cert_file" -pubkey -noout 2>/dev/null | \
          openssl pkey -pubin -outform pem > "$cert_pub" 2>/dev/null; then
          rm -f "$cert_pub" "$req_pub"
          return 1
        fi

        if ! openssl pkey -pubin -in "$pub_file" -outform pem > "$req_pub" 2>/dev/null; then
          rm -f "$cert_pub" "$req_pub"
          return 1
        fi

        cmp -s "$cert_pub" "$req_pub"
        local rc=$?
        rm -f "$cert_pub" "$req_pub"
        return "$rc"
      }

      # Check if key blobs already exist
      if [ -f "$PRIV_BLOB" ] && [ -f "$PUB_BLOB" ]; then
        PUB_HEAD=$(od -An -tx1 -N2 "$PUB_BLOB" 2>/dev/null | tr -d ' \n')
        if [ "$PUB_HEAD" != "0001" ] && [ "$PUB_HEAD" != "0023" ]; then
          echo "WARNING: Existing DevID public blob is not TPMT_PUBLIC, regenerating key blobs"
          rm -f "$PRIV_BLOB" "$PUB_BLOB" "$PUB_PEM" "$CERT_FILE" "$TSS_PUB_BLOB"
        fi
      fi

      if [ -f "$PRIV_BLOB" ] && [ -f "$PUB_BLOB" ]; then
        normalize_private_blob
        echo "DevID key blobs already exist for $VM_NAME"

        if ! rebuild_missing_public_artifacts; then
          clear_devid_material
          echo "Falling back to join_token attestation"
          echo "recover-public-failed" > /run/tpm/devid-status 2>/dev/null || true
          exit 0
        fi

        if [ -f "$PUB_PEM" ]; then
          local_cert_ok=0
          shared_cert_ok=0

          if [ -s "$CERT_FILE" ] && openssl x509 -in "$CERT_FILE" -noout >/dev/null 2>&1; then
            if cert_matches_pub "$CERT_FILE" "$PUB_PEM"; then
              local_cert_ok=1
            else
              echo "WARNING: Local DevID cert does not match TPM key, refreshing"
              rm -f "$CERT_FILE"
            fi
          elif [ -f "$CERT_FILE" ]; then
            echo "WARNING: Existing DevID cert is empty/invalid, regenerating"
            rm -f "$CERT_FILE"
          fi

          if [ -s "$SHARED_CERT_FILE" ] && openssl x509 -in "$SHARED_CERT_FILE" -noout >/dev/null 2>&1; then
            if cert_matches_pub "$SHARED_CERT_FILE" "$PUB_PEM"; then
              shared_cert_ok=1
            else
              echo "WARNING: Shared DevID cert does not match TPM key, requesting re-sign"
            fi
          elif [ -f "$SHARED_CERT_FILE" ]; then
            echo "WARNING: Shared DevID cert is empty/invalid, requesting refresh"
            rm -f "$SHARED_CERT_FILE"
          fi

          if [ "$local_cert_ok" -eq 1 ] && [ "$shared_cert_ok" -eq 1 ]; then
            echo "DevID cert already exists and matches TPM key, skipping provisioning"
            exit 0
          fi

          mkdir -p "$CSR_DIR"
          cp "$PUB_PEM" "$PUB_REQ_FILE"
          echo "Published DevID public key request to $PUB_REQ_FILE"
        else
          echo "WARNING: Missing $PUB_PEM for cert verification/re-signing request"
        fi

        echo "Key blobs exist but no cert yet, waiting for cert..."
      else
        echo "Generating DevID key for $VM_NAME..."

        if ! wait_for_tpm_ready; then
          echo "TPM not ready after 60s"
          echo "Falling back to join_token attestation"
          echo "no-tpm-ready" > /run/tpm/devid-status 2>/dev/null || true
          exit 0
        fi

        PRIMARY_READY=0
        for attempt in 1 2 3; do
          if create_srk_primary; then
            PRIMARY_READY=1
            break
          fi
          cleanup_contexts
          echo "Retrying primary creation... ($attempt/3)"
          sleep 2
        done
        if [ "$PRIMARY_READY" -eq 0 ]; then
          echo "Unable to create SRK primary"
          echo "Falling back to join_token attestation"
          echo "createprimary-failed" > /run/tpm/devid-status 2>/dev/null || true
          exit 0
        fi

        KEY_CREATED=0
        if tpm2_create -C "$DEVID_DIR/primary.ctx" -G rsa2048:rsassa-sha256 \
          -u "$TSS_PUB_BLOB" -r "$PRIV_BLOB" -c "$DEVID_DIR/devid.ctx" -Q 2>/dev/null; then
          KEY_CREATED=1
          echo "DevID key created with -G rsa2048:rsassa-sha256"
        elif tpm2_create -C "$DEVID_DIR/primary.ctx" -G rsa2048:rsassa \
          -u "$TSS_PUB_BLOB" -r "$PRIV_BLOB" -c "$DEVID_DIR/devid.ctx" -Q 2>/dev/null; then
          KEY_CREATED=1
          echo "DevID key created with -G rsa2048:rsassa"
        fi
        if [ "$KEY_CREATED" -ne 1 ]; then
          echo "Failed to create DevID key with supported tpm2_create syntaxes"
          echo "Falling back to join_token attestation"
          echo "keygen-failed" > /run/tpm/devid-status 2>/dev/null || true
          clear_devid_material
          exit 0
        fi

        READPUB_OK=0
        for _ in 1 2 3; do
          if tpm2_readpublic -c "$DEVID_DIR/devid.ctx" -f tpmt -o "$PUB_BLOB" -Q 2>/dev/null; then
            READPUB_OK=1
            break
          fi
          sleep 1
        done
        if [ "$READPUB_OK" -ne 1 ]; then
          echo "Failed to export DevID TPMT_PUBLIC blob"
          echo "Falling back to join_token attestation"
          echo "readpublic-tpmt-failed" > /run/tpm/devid-status 2>/dev/null || true
          clear_devid_material
          exit 0
        fi

        normalize_private_blob

        READPUB_PEM_OK=0
        for _ in 1 2 3; do
          if tpm2_readpublic -c "$DEVID_DIR/devid.ctx" -f pem -o "$PUB_PEM" -Q 2>/dev/null; then
            READPUB_PEM_OK=1
            break
          fi
          sleep 1
        done
        if [ "$READPUB_PEM_OK" -ne 1 ]; then
          echo "Failed to export DevID public key"
          echo "Falling back to join_token attestation"
          echo "readpublic-failed" > /run/tpm/devid-status 2>/dev/null || true
          clear_devid_material
          exit 0
        fi

        mkdir -p "$CSR_DIR"
        cp "$PUB_PEM" "$PUB_REQ_FILE"
        echo "Published DevID public key request to $PUB_REQ_FILE"

        # Clean up transient context files
        cleanup_contexts

        chown root:spire "$PRIV_BLOB" "$PUB_BLOB"
        chmod 0640 "$PRIV_BLOB" "$PUB_BLOB"
        echo "ready" > /run/tpm/devid-status 2>/dev/null || true
        echo "DevID key blobs created"
      fi

      # Wait for signed cert from admin-vm
      echo "Waiting for signed DevID certificate..."
      for i in $(seq 1 120); do
        if [ -s "$SHARED_CERT_FILE" ] && openssl x509 -in "$SHARED_CERT_FILE" -noout >/dev/null 2>&1; then
          if [ -f "$PUB_PEM" ] && ! cert_matches_pub "$SHARED_CERT_FILE" "$PUB_PEM"; then
            echo "WARNING: Signed cert for $VM_NAME does not match TPM key, waiting for refresh"
            sleep 2
            continue
          fi

          cp "$SHARED_CERT_FILE" "$CERT_FILE"
          chown root:spire "$CERT_FILE"
          chmod 0644 "$CERT_FILE"
          echo "DevID certificate received and stored at $CERT_FILE"
          exit 0
        elif [ -f "$SHARED_CERT_FILE" ]; then
          echo "WARNING: Signed cert for $VM_NAME is empty/invalid, waiting for refresh"
        fi
        if [ $((i % 10)) -eq 0 ]; then
          echo "Still waiting for cert... ($i/120)"
        fi
        sleep 2
      done

      echo "WARNING: Timed out waiting for DevID certificate"
      exit 1
    '';
  };
in
{
  _file = ./devid-provision.nix;

  options.ghaf.security.spiffe.devidProvision = {
    enable = lib.mkEnableOption "DevID key provisioning for SPIRE TPM attestation";

    vmName = lib.mkOption {
      type = lib.types.str;
      description = "Name of this VM (used in CSR CN and file paths)";
    };

    devidDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/spire/devid";
      description = "Directory for DevID key blobs and cert (on encrypted storage)";
    };

    csrDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/common/spire/devid/requests";
      description = "Directory where CSR is submitted (virtiofs, admin-vm readable)";
    };

    certDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/common/spire/devid/certs";
      description = "Directory where signed certs are placed by admin-vm (virtiofs)";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.spire-devid-provision = {
      description = "SPIRE DevID key provisioning (TPM)";
      wantedBy = [ "multi-user.target" ];
      before = [ "spire-agent.service" ];
      wants = [ "storagevm-enroll.service" ];
      after = [
        "local-fs.target"
        "storagevm-enroll.service"
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe spireDevidProvisionApp;
      };
    };
  };
}
