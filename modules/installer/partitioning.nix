{stdenvNoCC, ...}:
stdenvNoCC.mkDerivation {
  name = "ghaf-partitioning";
  src = ./.;
  phases = ["installPhase"];
  installPhase = ''
    mkdir -p $out
    cp $src/partitioning-scheme $out
    cp $src/example_secret.key $out
  '';
}
