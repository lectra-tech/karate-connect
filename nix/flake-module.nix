# flake-parts adapter: exposes `perSystem.karate-connect.runs.<name>` options
# and, for each entry, a package + app named `karate-test-<name>` that runs
# karate-connect's Karate CLI with that configuration.
#
# Usage in a consumer flake:
#
#   { inputs, ... }:
#   {
#     imports = [ inputs.karate-connect.flakeModules.default ];
#     perSystem = { ... }: {
#       karate-connect.runs.default = {
#         extensions = [ "rabbitmq" "kafka" ];
#         featuresPath = "src/test/features";
#         environmentVariables.RABBITMQ_HOST = "localhost";
#       };
#     };
#   }
#
#   $ nix run .#karate-test-default
{ lib, ... }:

{
  perSystem = { config, pkgs, lib, ... }:
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
          Named karate-connect test runs. Each entry produces a package and
          app named `karate-test-<name>` that invokes the karate-connect JAR
          with the given settings.
        '';
      };

      config = {
        packages = lib.mapAttrs' (name: b: lib.nameValuePair "karate-test-${name}" b.package) built;
        apps = lib.mapAttrs' (name: b: lib.nameValuePair "karate-test-${name}" b.app) built;
      };
    };
}
