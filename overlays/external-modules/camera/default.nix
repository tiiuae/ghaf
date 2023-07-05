{pkgs, ...} @ args:
with pkgs;
  buildGoModule rec {
    pname = "simplecam";
    version = "0.1";

    src = fetchFromGitHub {
      owner = "vladimirvivien";
      repo = "go4vl";
      rev = "018089c752cb092417d259661d6d8dc3874fc319";
      sha256 = "sha256-2JbTZCMhN98CJUzhjYTi/9rThobXVZ9pTTMDzGY1NVQ";
    };

    vendorSha256 = "sha256-s+Jbhf+N228HD8tUpQf7ovi0iFUfizMJheG6KLN+1sk";
    sourceRoot = "source/examples/simplecam";
  }
