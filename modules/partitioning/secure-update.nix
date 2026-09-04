# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.secureUpdate;
  verityCfg = config.ghaf.partitioning.verity;
  requiredPublic = [
    "PK.crt"
    "KEK.crt"
    "db.crt"
    "update.pub"
  ];

  buildConfigDir = inputs.secure-ab-build-config;
  buildConfigPath = buildConfigDir + "/config.json";
  buildConfig =
    if builtins.pathExists buildConfigPath then
      builtins.fromJSON (builtins.readFile buildConfigPath)
    else
      throw "secure-ab-build-config is missing config.json";
  buildConfigSchema = buildConfig.schema_version or null;
  buildConfigTrust = buildConfig.trust or null;
  buildConfigGeneration = buildConfig.generation or null;
  buildConfigInjectBootHealthFailure = buildConfig.inject_boot_health_failure or false;
  validBuildConfigGeneration = builtins.isInt buildConfigGeneration && buildConfigGeneration > 0;
  validBuildConfigInjectBootHealthFailure = builtins.isBool buildConfigInjectBootHealthFailure;
  generation = if validBuildConfigGeneration then buildConfigGeneration else 1;

  missingExternalPublic = lib.filter (
    name: !builtins.pathExists (buildConfigDir + "/${name}")
  ) requiredPublic;
  haveExternalPublic = buildConfigTrust == "external" && missingExternalPublic == [ ];
  fallbackUefiCertDir = ../secureboot/dev-keys;
  # RFC 8032 test-vector public key 1. Its private seed is public, so this key
  # is deliberately suitable only for pure evaluation and CI builds.
  fallbackUpdatePub = ../../config/secure-ab-ci/update.pub;
  publicFile =
    name:
    if haveExternalPublic then
      buildConfigDir + "/${name}"
    else if name == "update.pub" then
      fallbackUpdatePub
    else
      fallbackUefiCertDir + "/${name}";
  trustWarning =
    if haveExternalPublic then
      "${cfg.target}: using pure external public trust from secure-ab-build-config; private signing keys remain outside the Nix store."
    else
      "${cfg.target}: using repository CI-only trust from secure-ab-build-config; this image is restricted to debug build coverage and must not be deployed.";
  updaterEnvironment = {
    GHAF_UPDATE_TRUSTED_KEY = "/etc/ghaf/update/update.pub";
    GHAF_UKI_TRUSTED_CERT = "/etc/ghaf/update/db.crt";
    GHAF_UPDATE_TARGET = cfg.target;
    GHAF_ACCEPTED_GENERATION_FILE = cfg.acceptedGenerationFile;
  };
in
{
  options.ghaf.secureUpdate = {
    enable = lib.mkEnableOption "authenticated, health-gated A/B image updates";

    target = lib.mkOption {
      type = lib.types.strMatching ".+";
      description = "Exact target identifier accepted by this system's image updater.";
    };

    generation = lib.mkOption {
      type = lib.types.ints.positive;
      default = generation;
      defaultText = lib.literalExpression ''
        generation from the pure secure-ab-build-config flake input
      '';
      description = "Monotonic update generation embedded in the manifest and UKI.";
    };

    acceptedGenerationFile = lib.mkOption {
      type = lib.types.str;
      default = "/persist/common/ota/accepted-generation";
      description = "Persistent state advanced only after a generation passes the boot-health gate.";
    };

    injectBootHealthFailure = lib.mkOption {
      type = lib.types.bool;
      default =
        if validBuildConfigInjectBootHealthFailure then buildConfigInjectBootHealthFailure else false;
      readOnly = true;
      internal = true;
      description = "Whether the pure build input requests debug boot-health failure injection.";
    };

    externalPublicTrustConfigured = lib.mkOption {
      type = lib.types.bool;
      default = haveExternalPublic;
      readOnly = true;
      internal = true;
      description = "Whether evaluation imported a complete external public trust set.";
    };

    publicTrustDigests = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = lib.genAttrs requiredPublic (
        name: builtins.hashFile "sha256" cfg.publicTrustFiles.${name}
      );
      readOnly = true;
      internal = true;
      description = "SHA-256 digests of the public trust imported during pure evaluation.";
    };

    publicTrustFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {
        "PK.crt" = publicFile "PK.crt";
        "KEK.crt" = publicFile "KEK.crt";
        "db.crt" = publicFile "db.crt";
        "update.pub" = publicFile "update.pub";
      };
      readOnly = true;
      internal = true;
      description = "Public trust files selected during evaluation.";
    };

    uefiCertificateContents = lib.mkOption {
      type = lib.types.submodule {
        options = {
          PK = lib.mkOption { type = lib.types.lines; };
          KEK = lib.mkOption { type = lib.types.lines; };
          db = lib.mkOption { type = lib.types.lines; };
        };
      };
      default = {
        PK = builtins.readFile cfg.publicTrustFiles."PK.crt";
        KEK = builtins.readFile cfg.publicTrustFiles."KEK.crt";
        db = builtins.readFile cfg.publicTrustFiles."db.crt";
      };
      readOnly = true;
      internal = true;
      description = "UEFI public certificates selected by the shared update trust boundary.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = buildConfigSchema == 1;
        message = "${cfg.target}: secure-ab-build-config schema_version must be 1.";
      }
      {
        assertion = builtins.elem buildConfigTrust [
          "ci"
          "external"
        ];
        message = "${cfg.target}: secure-ab-build-config trust must be either `ci` or `external`.";
      }
      {
        assertion = validBuildConfigGeneration;
        message = "${cfg.target}: secure-ab-build-config generation must be a positive integer.";
      }
      {
        assertion = validBuildConfigInjectBootHealthFailure;
        message = "${cfg.target}: secure-ab-build-config inject_boot_health_failure must be a boolean.";
      }
      {
        assertion = !cfg.injectBootHealthFailure || config.ghaf.profiles.debug.enable;
        message = "${cfg.target}: boot-health failure injection is restricted to debug images.";
      }
      {
        assertion = buildConfigTrust != "external" || haveExternalPublic;
        message = "${cfg.target}: external secure-ab-build-config is missing required public trust files: ${lib.concatStringsSep ", " missingExternalPublic}.";
      }
      {
        assertion = buildConfigTrust != "ci" || config.ghaf.profiles.debug.enable;
        message = "${cfg.target}: repository CI-only secure A/B trust is restricted to debug images; supply a pure external secure-ab-build-config input.";
      }
      {
        assertion = verityCfg.rootSlotSizeMiB != null && verityCfg.veritySlotSizeMiB != null;
        message = "${cfg.target}: secure A/B requires explicit rootSlotSizeMiB and veritySlotSizeMiB capacities.";
      }
    ];
    warnings = [ trustWarning ];

    ghaf = {
      partitioning.verity = {
        inherit (cfg) target;
        inherit (cfg) generation;
      };
      boot-health = {
        inherit (cfg) acceptedGenerationFile;
        debugUnhealthyMicrovm = lib.mkIf cfg.injectBootHealthFailure "ghaf-boot-health-injection-probe";
      };
    };

    environment.etc = {
      "ghaf/update/update.pub".source = cfg.publicTrustFiles."update.pub";
      "ghaf/update/db.crt".source = cfg.publicTrustFiles."db.crt";
      "ghaf/update/trust-digests.json".text = builtins.toJSON {
        schema_version = 1;
        trust = buildConfigTrust;
        inherit (cfg) generation;
        sha256 = cfg.publicTrustDigests;
      };
      # Make otherwise bit-identical canary generations distinct in the closure,
      # and provide a simple runtime inventory value.
      "ghaf/update/generation".text = toString cfg.generation;
    };
    environment.sessionVariables = updaterEnvironment;
    # Remote OTA commands are children of the host GIVC agent, not login
    # shells, so environment.sessionVariables alone does not reach them.
    systemd.services."givc-${config.givc.host.network.agent.transport.name}".environment =
      lib.mkIf config.givc.host.enable updaterEnvironment;
    environment.systemPackages = [ pkgs.sbsigntool ];
  };
}
