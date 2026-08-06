# Plain adapter for consumers who don't use flake-parts (or devenv): evaluates
# the shared `karate-run-options.nix` module directly with `lib.evalModules`
# and builds the same package/app that the other two adapters produce.
#
# Usage in any flake, no flake-parts required:
#
#   { inputs, ... }:
#   {
#     outputs = { self, nixpkgs, karate-connect, ... }:
#       let
#         pkgs = import nixpkgs { system = "x86_64-linux"; };
#         run = karate-connect.lib.mkKarateRun {
#           inherit pkgs;
#           extensions = [ "rabbitmq" "kafka" ];
#           featuresPath = "src/test/features";
#         };
#       in
#       {
#         packages.x86_64-linux.karate-test = run.package;
#         apps.x86_64-linux.karate-test = run.app;
#       };
#   }
{ pkgs
, lib ? pkgs.lib
, name ? "default"
, ...
}@settings:

let
  # `pkgs`, `lib` and `name` are consumed here to select the JDK/JAR defaults
  # and to name the wrapper script; every remaining attribute is a setting
  # forwarded to the shared options module (extensions, featuresPath, ...).
  runSettings = builtins.removeAttrs settings [ "pkgs" "lib" "name" ];

  evaluated = lib.evalModules {
    modules = [
      (import ./karate-run-options.nix)
      { config = runSettings; }
    ];
    specialArgs = { inherit pkgs name; };
  };
in
import ./build-karate-run.nix {
  inherit pkgs lib name;
  cfg = evaluated.config;
}
