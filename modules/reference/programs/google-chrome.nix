# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    mkEnableOption
    types
    mkIf
    mkMerge
    literalExpression
    getExe
    optionalString
    ;
  cfg = config.ghaf.reference.programs.google-chrome;

  normalizedExtensions = map (
    ext:
    if builtins.isString ext then
      {
        id = ext;
        source = "webstore";
      }
    else if ext ? passthru && ext.passthru ? id then
      let
        inherit (ext.passthru) id;
        crxPath = "${ext}/${id}.crx";
        xmlPath = "${ext}/${id}.xml.template";
      in
      {
        inherit id;
        source = "local";
        crx = crxPath;
        xmlTemplate = xmlPath;
      }
    else
      throw "Invalid Chrome extension '${toString ext}'. Must be either a string (extension ID) or a package in 'packages/chrome-extensions/default.nix'."
  ) cfg.extensions;

  localExtensions = lib.filter (ext: ext.source == "local") normalizedExtensions;

  localExtensionDir =
    if localExtensions == [ ] then
      null
    else
      pkgs.runCommand "chrome-local-extensions" { } ''
        mkdir -p $out
        ${lib.concatStringsSep "\n" (
          map (ext: ''
            install -m644 ${ext.crx} $out/${ext.id}.crx
            install -m644 ${ext.xmlTemplate} $out/${ext.id}.xml
            substituteInPlace $out/${ext.id}.xml \
              --replace-fail "@UPDATE_BASE_URL@" "http://localhost:${toString cfg.localExtensionServer.port}/"
          '') localExtensions
        )}
        ${optionalString cfg.openInNormalExtension ''
          install -m644 ${pkgs.chrome-extensions.open-normal}/share/open-normal-extension.crx $out/${pkgs.chrome-extensions.open-normal.id}.crx
          install -m644 ${pkgs.chrome-extensions.open-normal}/share/update.xml $out/${pkgs.chrome-extensions.open-normal.id}.xml
        ''}
      '';

  forcelistEntries = map (
    ext:
    if ext.source == "local" then
      "${ext.id};http://localhost:${toString cfg.localExtensionServer.port}/${ext.id}.xml"
    else
      ext.id
  ) normalizedExtensions;
in
{
  _file = ./google-chrome.nix;

  options.ghaf.reference.programs.google-chrome = {
    enable = mkEnableOption "Google Chrome program settings";
    openInNormalExtension = mkEnableOption "browser extension to open links in the normal browser";
    defaultPolicy = mkOption {
      type = types.attrs;
      description = ''
        Google chrome policy options. A list of available policies
        can be found in the Chrome Enterprise documentation:
        <https://cloud.google.com/docs/chrome-enterprise/policies/>
        Make sure the selected policy is supported on Linux and your browser version.
      '';
      default = {
        PromptForDownloadLocation = true;
        AlwaysOpenPdfExternally = true;
        DefaultBrowserSettingEnabled = true;
        MetricsReportingEnabled = false;
        ExtensionInstallForcelist =
          forcelistEntries
          ++ (lib.optionals (cfg.openInNormalExtension && cfg.localExtensionServer.enable) [
            "${pkgs.chrome-extensions.open-normal.id};http://localhost:${toString cfg.localExtensionServer.port}/${pkgs.chrome-extensions.open-normal.id}.xml"
          ]);
      };
      example = literalExpression ''
        {
          PromptForDownloadLocation=true;
        }
      '';
    };

    extraOpts = mkOption {
      type = types.attrs;
      description = ''
        Extra google chrome policy options. A list of available policies
        can be found in the Chrome Enterprise documentation:
        <https://cloud.google.com/docs/chrome-enterprise/policies/>
        Make sure the selected policy is supported on Linux and your browser version.
      '';
      default = {
      };
      example = literalExpression ''
        {
          "BrowserSignin" = 0;
          "SyncDisabled" = true;
          "PasswordManagerEnabled" = false;
          "SpellcheckEnabled" = true;
          "SpellcheckLanguage" = [
            "de"
            "en-US"
          ];
        }
      '';
    };

    extensions = mkOption {
      type = with types; listOf (either str package);
      description = ''
        List of Chrome extensions to install.

        Each entry can be:

        - A **string**: the Chrome extension ID (fetched from the Web Store at runtime)
        - A **package**: a Nix derivation that provides a pre-fetched CRX file
          (for example, one defined in pkgs.chrome-extensions).

        When provided as a package, it must have the following passthru attributes:
        - id: the Chrome extension ID.
      '';

      default = [ ];
      example = literalExpression ''
        [
          "edacconmaakjimmfgnblocblbcdcpbko" # fetched at runtime from Chrome Web Store
          pkgs.chrome-extensions.session-buddy # pre-packaged, fetched at runtime from local server
        ]
      '';
    };

    localExtensionServer = {
      enable = mkOption {
        type = types.bool;
        default = lib.any (ext: ext.source == "local") normalizedExtensions;
        defaultText = literalExpression ''
          lib.any (ext: ext.source == "local") config.ghaf.reference.programs.google-chrome.extensions
        '';
        description = "Enable local extension update HTTP server";
      };
      port = mkOption {
        type = types.port;
        default = 8080;
        description = "Port for the local Chrome extension update server.";
      };
    };

    policyOwner = mkOption {
      type = types.str;
      default = "root";
      description = "Policy files owner";
    };

    policyOwnerGroup = mkOption {
      type = types.str;
      default = "root";
      description = "Policy files group";
    };
  };
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion =
          (lib.any (ext: ext.source == "local") normalizedExtensions) -> cfg.localExtensionServer.enable;
        message = "Local extensions are configured but localExtensionServer is disabled";
      }
      {
        assertion = cfg.openInNormalExtension -> cfg.localExtensionServer.enable;
        message = "openInNormalExtension requires localExtensionServer to be enabled";
      }
    ];

    environment.etc = mkMerge [
      {
        "opt/chrome/policies/managed/default.json" = {
          text = builtins.toJSON cfg.defaultPolicy;
          user = "${cfg.policyOwner}"; # Owner is proxy-user
          group = "${cfg.policyOwnerGroup}"; # Group is proxy-admin
          mode = "0664"; # Permissions: read/write for owner/group, no permissions for others
        };
        "opt/chrome/policies/managed/extra.json" = {
          text = builtins.toJSON cfg.extraOpts;
          user = "${cfg.policyOwner}"; # Owner is proxy-user
          group = "${cfg.policyOwnerGroup}"; # Group is proxy-admin
          mode = "0664"; # Permissions: read/write for owner/group, no permissions for others
        };
      }
      (mkIf (cfg.openInNormalExtension && config.ghaf.givc.enable) {
        "opt/chrome/native-messaging-hosts/fi.ssrc.open_normal.json" = {
          source = "${pkgs.chrome-extensions.open-normal}/fi.ssrc.open_normal.json";
        };

        "open-normal-extension.cfg" = {
          text = ''
            export GIVC_PATH="${pkgs.givc-cli}"
            export GIVC_OPTS="${config.ghaf.givc.cliArgs}"
          '';
        };
      })
    ];

    systemd.services.chrome-extension-server =
      mkIf (cfg.localExtensionServer.enable && localExtensionDir != null)
        {
          description = "Local Chrome extension update server";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            ExecStart = "${getExe pkgs.python3} -m http.server ${toString cfg.localExtensionServer.port} --directory ${localExtensionDir}";
            WorkingDirectory = "${localExtensionDir}";
            Restart = "always";
          };
        };
  };
}
