# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for NVIDIA Jetson Orin AGX/NX reference boards
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin;
  pythonWithCryptography = pkgs.python3.withPackages (ps: [ ps.cryptography ]);

  provisionEkCertsApp = pkgs.writeShellApplication {
    name = "ghaf-provision-ek-certs";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssl
      pythonWithCryptography
      pkgs.tpm2-tools
    ];
    text = ''
            set -euo pipefail

            export TPM2TOOLS_TCTI="device:/dev/tpmrm0"

            EK_NV_RSA="0x01C00002"
            EK_NV_ECC="0x01C0000A"
            WORKDIR="/run/ghaf-ek-provision"

            cleanup() {
              rm -rf "$WORKDIR"
            }
            trap cleanup EXIT

            mkdir -p "$WORKDIR"

            index_exists() {
              local idx="$1"
              timeout 5s tpm2_nvreadpublic "$idx" >/dev/null 2>&1
            }

            issue_cert_der() {
              local alg="$1"
              local out_der="$2"
              local subj="$3"
              local ek_ctx="$WORKDIR/ek-$alg.ctx"
              local ek_pub_blob="$WORKDIR/ek-$alg.pub"
              local ek_pub_pem="$WORKDIR/ek-$alg.pub.pem"
              local signer_key="$WORKDIR/selfsign-$alg.key.pem"
              local signer_cert="$WORKDIR/selfsign-$alg.ca.pem"

              timeout 20s tpm2_createek -Q -G "$alg" -c "$ek_ctx" -u "$ek_pub_blob"
              timeout 20s tpm2_readpublic -Q -c "$ek_ctx" -f pem -o "$ek_pub_pem"

              # Generate ephemeral self-signed signer and issue an EK leaf cert with EK public key.
              # This keeps all artifacts local to boot provisioning flow.
              openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
                -keyout "$signer_key" -out "$signer_cert" \
                -subj "/CN=Ghaf EK Self-Signed $alg"

              # Platform note: Orin class devices may boot with RTC reset (epoch/old time)
              # until network time sync becomes available. To keep TPM DevID attestation
              # functional even without immediate NTP, emit EK certs with a wide fixed
              # validity window instead of "now + N days" validity.
              python - "$ek_pub_pem" "$signer_key" "$signer_cert" "$out_der" "$subj" <<'PY'
      import datetime
      import sys

      from cryptography import x509
      from cryptography.hazmat.primitives import hashes, serialization
      from cryptography.x509.oid import NameOID


      def parse_subject(subject: str) -> x509.Name:
          oid_map = {
              "CN": NameOID.COMMON_NAME,
              "O": NameOID.ORGANIZATION_NAME,
              "OU": NameOID.ORGANIZATIONAL_UNIT_NAME,
              "C": NameOID.COUNTRY_NAME,
              "ST": NameOID.STATE_OR_PROVINCE_NAME,
              "L": NameOID.LOCALITY_NAME,
          }
          attrs = []
          for part in subject.split("/"):
              if not part or "=" not in part:
                  continue
              key, value = part.split("=", 1)
              oid = oid_map.get(key)
              if oid is not None:
                  attrs.append(x509.NameAttribute(oid, value))
          if not attrs:
              attrs = [x509.NameAttribute(NameOID.COMMON_NAME, "Ghaf EK")]
          return x509.Name(attrs)


      ek_pub_pem, signer_key_pem, signer_cert_pem, out_der, subject = sys.argv[1:]

      with open(ek_pub_pem, "rb") as f:
          ek_pub = serialization.load_pem_public_key(f.read())

      with open(signer_key_pem, "rb") as f:
          signer_key = serialization.load_pem_private_key(f.read(), password=None)

      with open(signer_cert_pem, "rb") as f:
          signer_cert = x509.load_pem_x509_certificate(f.read())

      not_before = datetime.datetime(1970, 1, 1, tzinfo=datetime.UTC)
      not_after = datetime.datetime(2100, 1, 1, tzinfo=datetime.UTC)

      cert = (
          x509.CertificateBuilder()
          .subject_name(parse_subject(subject))
          .issuer_name(signer_cert.subject)
          .public_key(ek_pub)
          .serial_number(x509.random_serial_number())
          .not_valid_before(not_before)
          .not_valid_after(not_after)
          .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
          .sign(private_key=signer_key, algorithm=hashes.SHA256())
      )

      with open(out_der, "wb") as f:
          f.write(cert.public_bytes(serialization.Encoding.DER))
      PY

              tpm2_flushcontext "$ek_ctx" >/dev/null 2>&1 || true
            }

            ensure_nv_cert() {
              local idx="$1"
              local alg="$2"
              local subj="$3"
              local der_file="$WORKDIR/ek-$alg.cert.der"

              if index_exists "$idx"; then
                echo "EK cert NV index $idx already present, skipping"
                return 0
              fi

              issue_cert_der "$alg" "$der_file" "$subj"
              local cert_size
              cert_size=$(stat -c %s "$der_file")

              tpm2_nvdefine "$idx" -C p -s "$cert_size" \
                -a "ppwrite|authwrite|ppread|authread|no_da|platformcreate"
              tpm2_nvwrite "$idx" -C p -i "$der_file"

              echo "Provisioned EK cert at NV index $idx ($alg, $cert_size bytes)"
            }

            ensure_nv_cert "$EK_NV_RSA" "rsa" "/CN=Jetson Orin fTPM EK RSA/O=Ghaf"
            ensure_nv_cert "$EK_NV_ECC" "ecc" "/CN=Jetson Orin fTPM EK ECC/O=Ghaf"
    '';
  };

  clearTpmLockoutApp = pkgs.writeShellApplication {
    name = "ghaf-clear-tpm-lockout";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.tpm2-tools
    ];
    text = ''
      set -euo pipefail

      export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
      STATUS_FILE="/run/tpm/lockout-status"

      mkdir -p /run/tpm

      is_in_lockout() {
        timeout -k 2s 5s tpm2_getcap properties-variable 2>/dev/null | grep -q "inLockout:[[:space:]]*1"
      }

      if ! timeout -k 2s 5s tpm2_getcap properties-variable >/dev/null 2>&1; then
        echo "tpm-unavailable" > "$STATUS_FILE"
        echo "TPM not ready for lockout check"
        exit 0
      fi

      if ! is_in_lockout; then
        echo "not-locked" > "$STATUS_FILE"
        echo "TPM is not in DA lockout mode"
        exit 0
      fi

      echo "TPM is in DA lockout mode, attempting clear"
      if timeout -k 2s 5s tpm2_dictionarylockout -c >/dev/null 2>&1; then
        sleep 1
        if is_in_lockout; then
          echo "still-locked" > "$STATUS_FILE"
          echo "WARNING: Lockout clear command completed but TPM remains locked"
        else
          echo "cleared" > "$STATUS_FILE"
          echo "TPM lockout cleared"
        fi
      else
        echo "clear-failed" > "$STATUS_FILE"
        echo "WARNING: Failed to clear TPM lockout"
      fi
    '';
  };

  exportEkBundleApp = pkgs.writeShellApplication {
    name = "ghaf-export-ek-endorsement-bundle";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssl
      pkgs.tpm2-tools
    ];
    text = ''
      set -euo pipefail

      export TPM2TOOLS_TCTI="device:/dev/tpmrm0"

      EK_NV_RSA="0x01C00002"
      EK_NV_ECC="0x01C0000A"
      WORKDIR="/run/ghaf-ek-export"
      OUTDIR="/persist/common/spire/ca"
      BUNDLE="${"$"}OUTDIR/endorsement-bundle.pem"

      cleanup() {
        rm -rf "$WORKDIR"
      }
      trap cleanup EXIT

      mkdir -p "$WORKDIR" "$OUTDIR"
      chmod 0755 /persist/common /persist/common/spire "$OUTDIR"
      : > "$BUNDLE"
      chmod 0644 "$BUNDLE"

      export_one() {
        local idx="$1"
        local pem="$2"
        local der
        der="$WORKDIR/$(basename "$pem" .pem).der"

        if ! timeout 5s tpm2_nvreadpublic "$idx" >/dev/null 2>&1; then
          echo "EK index $idx missing, skipping export"
          return 0
        fi

        timeout 8s tpm2_nvread "$idx" -o "$der"
        openssl x509 -inform DER -in "$der" -out "$pem"
        chmod 0644 "$pem"
        cat "$pem" >> "$BUNDLE"
      }

      export_one "$EK_NV_RSA" "$OUTDIR/ek-rsa.pem"
      export_one "$EK_NV_ECC" "$OUTDIR/ek-ecc.pem"
      echo "Wrote endorsement bundle to $BUNDLE"
    '';
  };

  normalizeTpmDaParamsApp = pkgs.writeShellApplication {
    name = "ghaf-normalize-tpm-da-params";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.tpm2-tools
    ];
    text = ''
      set -euo pipefail

      export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
      STATUS_FILE="/run/tpm/da-params-status"

      mkdir -p /run/tpm

      caps="$(timeout -k 2s 8s tpm2_getcap properties-variable 2>/dev/null || true)"
      if [ -z "$caps" ]; then
        echo "tpm-unavailable" > "$STATUS_FILE"
        exit 0
      fi

      if ! printf '%s\n' "$caps" | grep -qE 'TPM2_PT_MAX_AUTH_FAIL:[[:space:]]*(0x0|0)$'; then
        echo "ok" > "$STATUS_FILE"
        exit 0
      fi

      echo "normalizing" > "$STATUS_FILE"
      if timeout -k 2s 8s tpm2_dictionarylockout --setup-parameters \
        --max-tries=3 \
        --recovery-time=1000 \
        --lockout-recovery-time=1000 >/dev/null 2>&1; then
        echo "normalized" > "$STATUS_FILE"
      else
        echo "normalize-failed" > "$STATUS_FILE"
      fi
    '';
  };

  firmwareEkbImage =
    pkgs.buildPackages.runCommand "ghaf-eks-t234"
      {
        nativeBuildInputs = [
          pkgs.buildPackages.openssl
          pkgs.buildPackages.nvidia-jetpack.genEkb
        ];
      }
      ''
                        set -euo pipefail

                        mkdir -p "$out"

                        # Development key for unfused devices (OEM_K1 all-zero key).
                cat > oem_k1.key <<'EOF'
        0x0000000000000000000000000000000000000000000000000000000000000000
        EOF

                # Avoid interactive prompt in gen_ekb.py by providing UEFI auth key.
                cat > auth.key <<'EOF'
        0x00000000000000000000000000000000
        EOF

                        openssl req -x509 -newkey rsa:2048 -sha256 -nodes \
                          -keyout ek-rsa-key.pem -out ek-rsa.pem \
                          -subj "/CN=Jetson Orin fTPM EK RSA/O=Ghaf" \
                          -days 36500

                        openssl ecparam -name prime256v1 -genkey -noout -out ek-ecc-key.pem
                        openssl req -x509 -new -sha256 \
                          -key ek-ecc-key.pem -out ek-ecc.pem \
                          -subj "/CN=Jetson Orin fTPM EK ECC/O=Ghaf" \
                          -days 36500

                        openssl x509 -in ek-rsa.pem -outform DER -out ek-rsa.der
                        openssl x509 -in ek-ecc.pem -outform DER -out ek-ecc.der

                ${pkgs.buildPackages.nvidia-jetpack.genEkb}/bin/gen_ekb.py \
                  -chip t234 \
                  -oem_k1_key oem_k1.key \
                  -in_auth_key auth.key \
                  -in_ftpm_rsa_ek_cert ek-rsa.der \
                  -in_ftpm_ec_ek_cert ek-ecc.der \
                  -out "$out/eks_t234.img"
      '';

  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;
in
{
  _file = ./jetson-orin.nix;

  options.ghaf.hardware.nvidia.orin = {
    # Enable the Orin boards
    enable = mkEnableOption "Orin hardware";

    flashScriptOverrides.onlyQSPI = mkEnableOption "to only flash QSPI partitions, i.e. disable flashing of boot and root partitions to eMMC";

    flashScriptOverrides.preFlashCommands = mkOption {
      description = "Commands to run before the actual flashing";
      type = types.str;
      default = "";
    };

    somType = mkOption {
      description = "SoM config Type (NX|AGX32|AGX64|Nano)";
      type = types.str;
      default = "agx";
    };

    carrierBoard = mkOption {
      description = "Board Type";
      type = types.str;
      default = "devkit";
    };

    kernelVersion = mkOption {
      description = "Kernel version";
      type = types.str;
      default = "bsp-default";
    };

    runtimeEkProvision.enable = mkOption {
      description = "Provision EK certificates into TPM NV indices at runtime";
      type = types.bool;
      default = true;
    };

    lockoutClear.enable = mkOption {
      description = "Attempt TPM DA lockout clear during host boot";
      type = types.bool;
      default = false;
    };

    daNormalize.enable = mkOption {
      description = "Normalize TPM dictionary-attack parameters when maxAuthFail is zero";
      type = types.bool;
      default = true;
    };
  };

  config = mkIf cfg.enable {
    hardware.nvidia-jetpack.firmware.eksFile = "${firmwareEkbImage}/eks_t234.img";
    hardware.nvidia-jetpack.kernel.version = "${cfg.kernelVersion}";
    nixpkgs.hostPlatform.system = "aarch64-linux";

    ghaf.hardware = {
      aarch64.systemd-boot-dtb.enable = true;
      passthrough = {
        vhotplug.enable = true;
        usbQuirks.enable = true;
      };
    };

    boot = {
      loader = {
        efi.canTouchEfiVariables = true;
        systemd-boot.enable = true;
      };

      modprobeConfig.enable = true;

      # Load fTPM module early so EK provisioning and storage setup services
      # do not race module autoload during boot.
      kernelModules = [
        "tpm_ftpm_tee"
      ];

      kernelPatches = [
        {
          name = "vsock-config";
          patch = null;
          structuredExtraConfig = with lib.kernel; {
            VHOST = yes;
            VHOST_MENU = yes;
            VHOST_IOTLB = yes;
            VHOST_VSOCK = yes;
            VSOCKETS = yes;
            VSOCKETS_DIAG = yes;
            VSOCKETS_LOOPBACK = yes;
            VIRTIO_VSOCKETS_COMMON = yes;
          };
        }
        {
          name = "ftpm-config";
          patch = null;
          structuredExtraConfig = with lib.kernel; {
            EXPERT = yes;
            TCG_FTPM_TEE = module;
            # Disable TPM hwrng to prevent constant fTPM polling pressure
            # that can saturate the OP-TEE single-lane fTPM TA under load.
            HW_RANDOM_TPM = no;
          };
        }
      ];
    };

    systemd.services.ghaf-clear-tpm-lockout = mkIf cfg.lockoutClear.enable {
      description = "Attempt to clear TPM DA lockout before VM startup";
      wantedBy = [ "multi-user.target" ];
      after = [
        "local-fs.target"
        "systemd-modules-load.service"
        "dev-tpmrm0.device"
      ];
      requires = [ "dev-tpmrm0.device" ];
      unitConfig.ConditionPathExists = "/dev/tpmrm0";

      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "20s";
        TimeoutStopSec = "2s";
        KillMode = "control-group";
        UMask = "0077";
        ExecStart = lib.getExe clearTpmLockoutApp;
      };
    };

    systemd.services.ghaf-normalize-tpm-da-params = mkIf cfg.daNormalize.enable {
      description = "Normalize TPM dictionary-attack parameters";
      wantedBy = [ "multi-user.target" ];
      after = [
        "local-fs.target"
        "systemd-modules-load.service"
        "dev-tpmrm0.device"
      ];
      requires = [ "dev-tpmrm0.device" ];
      unitConfig.ConditionPathExists = "/dev/tpmrm0";

      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "20s";
        TimeoutStopSec = "2s";
        KillMode = "control-group";
        UMask = "0077";
        ExecStart = lib.getExe normalizeTpmDaParamsApp;
      };
    };

    systemd.services.ghaf-provision-ek-certs = mkIf cfg.runtimeEkProvision.enable {
      description = "Provision fTPM EK certificates into standard NV indices";
      wantedBy = [ "multi-user.target" ];
      after = [
        "local-fs.target"
        "systemd-modules-load.service"
        "dev-tpmrm0.device"
      ]
      ++ lib.optionals cfg.daNormalize.enable [
        "ghaf-normalize-tpm-da-params.service"
      ]
      ++ lib.optionals cfg.lockoutClear.enable [
        "ghaf-clear-tpm-lockout.service"
      ];
      requires = [ "dev-tpmrm0.device" ];
      unitConfig.ConditionPathExists = "/dev/tpmrm0";
      unitConfig.OnSuccess = [ "ghaf-export-ek-endorsement-bundle.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "90s";
        UMask = "0077";
        ExecStart = lib.getExe provisionEkCertsApp;
        ExecStartPost = "${pkgs.systemd}/bin/systemctl --no-block start ghaf-export-ek-endorsement-bundle.service";
      };
    };

    systemd.services.ghaf-export-ek-endorsement-bundle = {
      description = "Export EK certs and build endorsement CA bundle";
      wantedBy = [ "multi-user.target" ];
      after = [
        "local-fs.target"
        "systemd-modules-load.service"
      ]
      ++ lib.optionals cfg.lockoutClear.enable [
        "ghaf-clear-tpm-lockout.service"
      ]
      ++ lib.optionals cfg.runtimeEkProvision.enable [
        "ghaf-provision-ek-certs.service"
      ];
      unitConfig.ConditionPathExists = "/dev/tpmrm0";

      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "45s";
        UMask = "0077";
        ExecStart = lib.getExe exportEkBundleApp;
      };
    };

    services.nvpmodel = {
      enable = lib.mkDefault true;
      # Enable all CPU cores, full power consumption (50W on AGX, 25W on NX)
      profileNumber = lib.mkDefault 3;
    };

    hardware.deviceTree = {
      enable = lib.mkDefault true;
      # Add the include paths to build the dtb overlays
      dtboBuildExtraIncludePaths = [
        "${lib.getDev config.hardware.deviceTree.kernelPackage}/lib/modules/${config.hardware.deviceTree.kernelPackage.modDirVersion}/source/nvidia/soc/t23x/kernel-include"
      ];
    };

    # NOTE: "-nv.dtb" files are from NVIDIA's BSP
    # Versions of the device tree without PCI passthrough related
    # modifications.
  };
}
