# Copyright 2024 TII (SSRC) and the Ghaf contributors
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
    optionalString
    concatStringsSep
    filter
    types
    mkIf
    mkMerge
    literalExpression
    any
    getExe
    ;
  cfg = config.ghaf.reference.programs.google-chrome;

  extensionType = types.submodule (
    { config, ... }:
    {
      options = {
        id = mkOption {
          type = types.str;
          description = "Chrome extension ID.";
        };

        source = mkOption {
          type = types.enum [
            "webstore"
            "local"
          ];
          default = "webstore";
          description = ''
            Where to fetch the extension from.
            - "webstore": fetched at runtime directly from Chrome Web Store.
            - "local": fetched at build time and served via local HTTP.
          '';
        };

        version = mkOption {
          type = types.str;
          description = "Extension version used in generated update.xml.";
          apply =
            value:
            if config.source == "local" && value == null then
              throw "local Chrome extensions must specify a version"
            else
              value;
        };

        hash = mkOption {
          type = types.str;
          description = ''
            Hash to use for the CRX derivation.

            Leave empty on first build to get the hash automatically.
          '';
          apply =
            value:
            if config.source == "local" && value == null then
              throw "local Chrome extensions must specify a hash"
            else
              value;
        };
      };
    }
  );

  normalizeExtension =
    ext:
    # If only the ID is given, assume we should fetch from the webstore at runtime
    if builtins.isString ext then
      {
        id = ext;
        source = "webstore";
      }
    else
      ext;

  extensions = map normalizeExtension cfg.extensions;

  localExtensions = filter (ext: ext.source == "local") extensions;

  # Fetch CRX files from the Chrome Web Store for locally hosted extensions
  fetchedExtensions = map (
    ext:
    let
      crxUrl =
        "https://clients2.google.com/service/update2/crx?response=redirect"
        + "&prodversion=${pkgs.google-chrome.version}"
        + "&acceptformat=crx3"
        + "&x=id%3D${ext.id}%26installsource%3Dondemand%26uc";
    in
    rec {
      inherit (ext) id version hash;
      crx = pkgs.fetchurl {
        url = crxUrl;
        name = "${id}.crx";
        inherit hash;
      };

      updateXml = pkgs.writeText "${id}.xml" ''
        <?xml version="1.0" encoding="UTF-8"?>
        <gupdate xmlns="http://www.google.com/update2/response" protocol="2.0">
          <app appid="${id}">
            <updatecheck codebase="http://localhost:${toString cfg.localExtensionServer.port}/${id}.crx" version="${version}"/>
          </app>
        </gupdate>
      '';
    }
  ) localExtensions;

  localExtensionDir =
    if fetchedExtensions == [ ] then
      null
    else
      pkgs.runCommand "chrome-local-extensions" { } ''
        mkdir -p $out
        ${concatStringsSep "\n" (
          map (e: ''
            install -m644 ${e.crx} $out/${e.id}.crx
            install -m644 ${e.updateXml} $out/${e.id}.xml
          '') fetchedExtensions
        )}
        ${optionalString cfg.openInNormalExtension ''
          install -m644 ${pkgs.open-normal-extension}/share/open-normal-extension.crx $out/${pkgs.open-normal-extension.id}.crx
          install -m644 ${pkgs.open-normal-extension}/share/update.xml $out/${pkgs.open-normal-extension.id}.xml
        ''}
      '';

  forcelistEntries = map (
    ext:
    if ext.source == "local" then
      "${ext.id};http://localhost:${toString cfg.localExtensionServer.port}/${ext.id}.xml"
    else
      ext.id
  ) extensions;
in
{
  options.ghaf.reference.programs.google-chrome = {
    enable = mkEnableOption "Enable Google chrome program settings";
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
            "${pkgs.open-normal-extension.id};http://localhost:${toString cfg.localExtensionServer.port}/${pkgs.open-normal-extension.id}.xml"
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
      type = with types; listOf (either str extensionType);
      description = ''
        List of Chrome extensions to install.

        Each can be:
        - A string (extension ID, fetched from Chrome Web Store normally)
        - Or an attribute set with:
          `id` (string): Extension ID
          `source` ("webstore" or "local"): where to fetch the extension from
            "local" means the extension will be fetched and installed at build time
            from the Chrome Web Store and served locally via HTTP
            This is useful if, for example, the target system does not have internet access
            and you want the extension to be available immediately
          `version` (string): Version used in generated update.xml
          `hash` (string): Hash to use for the CRX derivation
            Leave empty on first build to get the hash automatically
      '';
      default = [ ];
      example = literalExpression ''
        [
          "xbghaffnmohnlmojndnbenakcmddkbik"
          {
            id = "iaiomicjabeggjcfkbimgmglanimpnae";
            source = "local";
            version = "6.4.1";
            hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          }
        ]
      '';
    };

    localExtensionServer = {
      enable = mkOption {
        type = types.bool;
        default = any (ext: ext.source == "local") extensions;
        defaultText = literalExpression ''
          any (ext: ext.source == "local") config.ghaf.reference.programs.google-chrome.extensions
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
        assertion = (any (ext: ext.source == "local") extensions) -> cfg.localExtensionServer.enable;
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
          source = "${pkgs.open-normal-extension}/fi.ssrc.open_normal.json";
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
