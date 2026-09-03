# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.secureUpdate;
  verityCfg = config.ghaf.partitioning.verity;
  keyDir = builtins.getEnv "GHAF_DEV_KEY_DIR";
  generationText = builtins.getEnv "GHAF_UPDATE_GENERATION";
  generation =
    if generationText == "" then
      1
    else if builtins.match "[1-9][0-9]*" generationText != null then
      lib.toInt generationText
    else
      throw "GHAF_UPDATE_GENERATION must be a positive decimal integer";

  requiredPublic = [
    "PK.crt"
    "KEK.crt"
    "db.crt"
    "update.pub"
  ];
  missingPublic = lib.filter (name: !builtins.pathExists "${keyDir}/${name}") requiredPublic;
  haveExternalPublic = keyDir != "" && missingPublic == [ ];
  externalPublicFile =
    name:
    builtins.path {
      path = builtins.toPath "${keyDir}/${name}";
      name = "ghaf-dev-${name}";
    };
  fallbackUefiCertDir = ../secureboot/dev-keys;
  # RFC 8032 test-vector public key 1. Its private seed is public, so this key
  # is deliberately suitable only for pure evaluation and CI builds.
  fallbackUpdatePub = pkgs.runCommand "ghaf-ci-only-update.pub" { } ''
    printf '%s' '11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=' \
      | ${pkgs.buildPackages.coreutils}/bin/base64 --decode > "$out"
    test "$(${pkgs.buildPackages.coreutils}/bin/wc -c < "$out")" -eq 32
  '';
  publicFile =
    name: if haveExternalPublic then externalPublicFile name else fallbackUefiCertDir + "/${name}";
  trustWarning =
    if haveExternalPublic then
      "${cfg.target}: using external public trust from GHAF_DEV_KEY_DIR; private signing keys remain outside the Nix store."
    else
      "${cfg.target}: GHAF_DEV_KEY_DIR is unset; using repository development public trust for evaluation/build only. Secure A/B deployment and update signing require GHAF_DEV_KEY_DIR from ghaf-dev-keygen.";
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
        GHAF_UPDATE_GENERATION, or 1 when it is unset
      '';
      description = "Monotonic update generation embedded in the manifest and UKI.";
    };

    acceptedGenerationFile = lib.mkOption {
      type = lib.types.str;
      default = "/persist/common/ota/accepted-generation";
      description = "Persistent state advanced only after a generation passes the boot-health gate.";
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
      default =
        if haveExternalPublic then
          lib.genAttrs requiredPublic (name: builtins.hashFile "sha256" "${keyDir}/${name}")
        else
          { };
      readOnly = true;
      internal = true;
      description = "SHA-256 digests of external public trust imported during evaluation.";
    };

    publicTrustFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {
        "PK.crt" = publicFile "PK.crt";
        "KEK.crt" = publicFile "KEK.crt";
        "db.crt" = publicFile "db.crt";
        "update.pub" = if haveExternalPublic then externalPublicFile "update.pub" else fallbackUpdatePub;
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
        PK = builtins.readFile (publicFile "PK.crt");
        KEK = builtins.readFile (publicFile "KEK.crt");
        db = builtins.readFile (publicFile "db.crt");
      };
      readOnly = true;
      internal = true;
      description = "UEFI public certificates selected by the shared update trust boundary.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = verityCfg.rootSlotSizeMiB != null && verityCfg.veritySlotSizeMiB != null;
        message = "${cfg.target}: secure A/B requires explicit rootSlotSizeMiB and veritySlotSizeMiB capacities.";
      }
    ]
    ++ lib.optional (keyDir != "") {
      assertion = haveExternalPublic;
      message = "${cfg.target}: GHAF_DEV_KEY_DIR is set but missing required public trust files: ${lib.concatStringsSep ", " missingPublic}.";
    };
    warnings = [ trustWarning ];

    ghaf = {
      partitioning.verity = {
        inherit (cfg) target;
        inherit (cfg) generation;
      };
      boot-health.acceptedGenerationFile = cfg.acceptedGenerationFile;
    };

    environment.etc = {
      "ghaf/update/update.pub".source = cfg.publicTrustFiles."update.pub";
      "ghaf/update/db.crt".source = cfg.publicTrustFiles."db.crt";
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
