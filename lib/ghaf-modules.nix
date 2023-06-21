{lib}: let
  inherit (builtins) readFile filter;
  inherit (lib) filesystem hasInfix hasSuffix;

  isDesiredFile = path: hasSuffix ".nix" path && hasInfix "options" (readFile path);
  modulesDirectoryFiles = filesystem.listFilesRecursive ../modules;
in
  filter isDesiredFile modulesDirectoryFiles
