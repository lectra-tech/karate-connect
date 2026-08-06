{
  description = ''
    Reusable Nix module for running karate-connect (https://github.com/lectra-tech/karate-connect)
    Karate tests, with every setting (extensions, features path, output, tags,
    threads, environment variables, ...) customizable. Import it from a
    flake-parts flake (`flakeModules.default`), a plain flake
    (`lib.mkKarateRun`), or a devenv project (`devenvModules.default`).
  '';

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Only used to dogfood/test the module against this repo's own features
    # below. Consumers of `flakeModules.default` do NOT need flake-parts
    # themselves; they just import the module into their own flake-parts
    # configuration.
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      imports = [ ./nix/flake-module.nix ];

      flake = {
        # Consumer-facing outputs.
        flakeModules.default = import ./nix/flake-module.nix;
        devenvModules.default = import ./nix/devenv-module.nix;
        lib.mkKarateRun = import ./nix/lib.nix;
      };

      perSystem = { config, pkgs, lib, ... }: {
        # Dogfood the module against this repo's own, fully-mocked kubernetes
        # feature (no real `kubectl`/network access needed: the scenario
        # reads `mockJobDescription` instead of shelling out). This proves the
        # whole chain end-to-end: fetching the pinned JAR, building the
        # wrapper, and actually running Karate.
        karate-connect.runs.kubernetes-smoke = {
          extensions = [ "kubernetes" ];
          featuresPath = "src/test/resources";
          karateConfigDir = "src/test/resources";
          tags = "@kubernetes";
        };

        checks.kubernetes-smoke = pkgs.runCommand "karate-connect-kubernetes-smoke"
          {
            nativeBuildInputs = [ config.packages.karate-test-kubernetes-smoke ];
          }
          ''
            mkdir -p src/test
            cp -r ${./src/test/resources} src/test/resources
            chmod -R u+w src
            karate-run-kubernetes-smoke
            touch $out
          '';
      };
    };
}
