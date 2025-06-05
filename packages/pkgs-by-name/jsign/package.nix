{ lib, fetchFromGitHub, jre, makeWrapper, maven }:

maven.buildMavenPackage rec {
  pname = "jsign";
  version = "7.1";

  src = fetchFromGitHub {
    owner = "ebourg";
    repo = pname;
    rev = "refs/tags/${version}";
    hash = "sha256-+ZErUCTbAI4uzhZGVQ5+awi4N4hnL3RD6SuoNdiXxBs=";
  };

  mvnHash = "sha256-k/04IHQ90OxSlOzstCTe2QhddZNpqPFsTqkVLjLHArM=";

  nativeBuildInputs = [ makeWrapper ];

  # some tests fail trying to make HTTP requests to unreachable domains
  doCheck = false;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/jsign
    install -Dm644 jsign/target/jsign-${version}.jar $out/share/jsign

    makeWrapper ${jre}/bin/java $out/bin/jsign \
      --add-flags "-jar $out/share/jsign/jsign-${version}.jar"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Java implementation of Microsoft Authenticode for signing Windows executables, installers & scripts";
    homepage = "https://github.com/ebourg/jsign";
    license = licenses.asl20;
  };
}
