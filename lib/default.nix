{
  self,
  nixpkgs,
}: let
  release = nixpkgs.lib.strings.fileContents ../.version;
  versionSuffix = ".${nixpkgs.lib.substring 0 8 (self.lastModifiedDate or self.lastModified or "19700101")}.${self.shortRev or "dirty"}";
  version = release + versionSuffix;
in {
  inherit release versionSuffix version;
}
