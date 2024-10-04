# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.services.printer;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    optionalAttrs
    hasAttr
    ;
in
{
  options.ghaf.services.printer = {
    enable = mkEnableOption "Printer configuration for app-vms";
    name = mkOption {
      type = types.string;
      description = "App-vm name for storage-vm";
    };
  };
  config = mkIf cfg.enable {

    services.printing.enable = true;
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      reflector = true;
    };
    environment.etc."chromium/bookmarks.html".text =
      ''
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <!-- This is an automatically generated file.
             It will be read and overwritten.
             DO NOT EDIT! -->
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3 ADD_DATE="1726234624" LAST_MODIFIED="1726234726" PERSONAL_TOOLBAR_FOLDER="true">Bookmarks bar</H3>
            <DL><p>
      ''
      + "<DT><A HREF=\"http://localhost:631/\" ADD_DATE=\"1726234644\" ICON=\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkW"
      + "g2AAABj0lEQVQ4jZWST8tBQRTG589x76SmW8qNlZuNkrg2VpQUFr6HjU/lS4gs2NmxslBSysaGy2TkGjPvYuqm3pVZnZ7nd86p5wwej8folwdRFP3WcLvdft5gjMEYI4S+C2v"
      + "/1+F6vWKMjTHGGEqp1joZZjlKqVIKIUQIMcbA5XKJ4xgAAEAIwRhL+hljSikhhOd51nVdl2az2UwmMxwOW63W6/Vqt9vr9XowGARB0Ov1giBIpVLdbrdSqZzP5+PxCEKI0Wi0"
      + "2Wwmk0mj0SgWi1JK3/cB4H6/c87DMHQcRwjx+XwwxoQQIoTwfb9Wq+VyOa11uVzmnEspC4XCfD5fLBb7/T6fzzebTSklLZVKu90uDMNqtTqdTk+nU7/fX61Wh8Nhu93OZjPOe"
      + "b1ej6JouVw+Hg/c6XSUUs/nEyHkOI7WWmttw8EYp9NpKWUcx5RSQojrumCMAQDP8xBCFrUp2WTf77fjOIwxm7LWGqyhtbapWzU5hb1X4mKMwULfgy2U3M4qiQvfxDf6X7E1+e"
      + "nnIYT+ABKG4uJL4UAgAAAAAElFTkSuQmCC\">Printing</A>"
      + ''
            </DL><p>
        </DL><p>
      '';
    programs.chromium.initialPrefs = {
      "import_bookmarks" = false;
      "distribution" = {
        "import_bookmarks" = false;
        "import_bookmarks_from_file" = "/etc/chromium/bookmarks.html";
        "bookmark_bar" = {
          "show_on_all_tabs" = true;
        };
      };
    };
    ghaf = optionalAttrs (hasAttr "storagevm" config.ghaf) {
      storagevm = {
        enable = true;
        inherit (cfg) name;
        directories = [ "/etc/cups/" ];
      };
    };
  };
}
