# devenv adapter: exposes `karate-connect.runs.<name>` options at the top of a
# consumer's `devenv.nix`, wiring each run's JDK/JAR into `packages` and
# adding a `karate-<name>` script that invokes the Karate CLI.
#
# Usage in a consumer's devenv.yaml:
#
#   inputs:
#     karate-connect:
#       url: github:lectra-tech/karate-connect
#
# and devenv.nix:
#
#   { inputs, ... }:
#   {
#     imports = [ inputs.karate-connect.devenvModules.default ];
#     karate-connect.runs.default = {
#       extensions = [ "rabbitmq" "kafka" ];
#       featuresPath = "src/test/features";
#     };
#   }
#
#   $ devenv shell -- karate-default
{ pkgs, lib, config, ... }:

let
  built = lib.mapAttrs
    (name: cfg: import ./build-karate-run.nix { inherit pkgs lib name cfg; })
    config.karate-connect.runs;
in
{
  options.karate-connect.runs = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submoduleWith {
      modules = [ (import ./karate-run-options.nix) ];
      specialArgs = { inherit pkgs; };
    });
    default = { };
    description = ''
      Named karate-connect test runs. Each entry adds a `karate-<name>`
      script to the devenv shell that invokes the karate-connect JAR with the
      given settings.
    '';
  };

  config = {
    # No extra `packages` entry needed: `writeShellApplication` already wraps
    # each script with its own `jdk` on PATH (via `runtimeInputs`).
    scripts = lib.mapAttrs'
      (name: b: lib.nameValuePair "karate-${name}" { exec = ''exec ${b.package}/bin/karate-run-${name} "$@"''; })
      built;
  };
}
