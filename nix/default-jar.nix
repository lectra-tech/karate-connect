# Pinned, reproducible fetch of a published karate-connect standalone JAR from
# GitHub Releases (https://github.com/lectra-tech/karate-connect/releases).
#
# karate-connect itself is a Gradle/Kotlin project; this flake does not try to
# rebuild it from source (fragile & slow under Nix). Instead it fetches the
# already-published fat JAR and pins it by content hash, exactly like the
# project's own Docker images do (`karate-connect-<version>-standalone.jar`).
#
# Usage:
#   import ./default-jar.nix { inherit pkgs; }
# or, to pin a different release:
#   import ./default-jar.nix { inherit pkgs; version = "0.5.2"; hash = "sha256-..."; }
{ pkgs
, version ? "0.5.3"
, hash ? "sha256-gjOjHqTpeIv5jI5EK8l8Yw89b/PO7QwjgrLiKxrYjh0="
}:

pkgs.fetchurl {
  name = "karate-connect-${version}-standalone.jar";
  url = "https://github.com/lectra-tech/karate-connect/releases/download/v${version}/karate-connect-${version}-standalone.jar";
  inherit hash;
}
