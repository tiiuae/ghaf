{
  self,
  lib,
}: let
  release = lib.strings.fileContents ../.version;
  versionSuffix = ".${lib.substring 0 8 (self.lastModifiedDate or self.lastModified or "19700101")}.${self.shortRev or "dirty"}";
  version = release + versionSuffix;
in {
  inherit release versionSuffix version;
  modules = import ./ghaf-modules.nix {inherit lib;};
}
