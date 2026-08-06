# Shared option set describing a single "karate-connect run": what JAR to use,
# which extensions to load, where the features/config/output live, and how to
# invoke the Karate CLI. Every consumer-facing adapter (flake-parts module,
# plain `lib.mkKarateRun`, devenv module) wraps *this exact* module as a
# `types.submodule`, so the three integration styles can never drift apart.
#
# Intended usage: `lib.types.submodule (import ./karate-run-options.nix)`
# evaluated with `pkgs` and the attribute `name` available as module args
# (flake-parts, devenv and `lib.evalModules` all provide both).
{ lib, pkgs, name ? "default", ... }:

let
  inherit (lib) types mkOption;
  defaultJar = import ./default-jar.nix { inherit pkgs; };
in
{
  options = {
    jar = mkOption {
      type = types.package;
      default = defaultJar;
      defaultText = lib.literalExpression ''import ./default-jar.nix { inherit pkgs; }'';
      description = ''
        The karate-connect standalone JAR to run. Defaults to a pinned release
        fetched from GitHub Releases. Override with a custom build (e.g. a
        fork, or a locally built `-standalone.jar`) if needed.
      '';
    };

    jdk = mkOption {
      type = types.package;
      default = pkgs.temurin-bin-21;
      defaultText = lib.literalExpression "pkgs.temurin-bin-21";
      description = ''
        JDK used to run the JAR. Defaults to JDK 21, matching karate-connect's
        own Gradle toolchain and Docker builder image.
      '';
    };

    extensions = mkOption {
      type = types.listOf (types.enum [ "rabbitmq" "kafka" "snowflake" "dbt" "kubernetes" ]);
      default = [ ];
      description = ''
        Extensions to load, passed as `-Dextensions=<ext1>,<ext2>,...`. `base`
        is always loaded by karate-connect itself regardless of this list.
      '';
    };

    featuresPath = mkOption {
      type = types.str;
      default = "features";
      description = ''
        Path to the feature file(s) or directory to run, resolved at runtime
        against the invoking shell's working directory (kept as a plain
        string, not a Nix path, so it is never copied into the store).
      '';
    };

    featuresMountPath = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/features";
      description = ''
        Absolute path at which `featuresPath` should appear to the running
        JVM, bind-mounted at run time -- the same remapping Docker usage does
        with `-v <features_path>:/features` (see the Docker image's
        `VOLUME /features`). Implemented with `bubblewrap` (`bwrap`) on Linux,
        or `bindfs` on Darwin (see below); evaluation fails with a clear error
        on any other platform.

        Feature files are sometimes written to read fixtures via a hardcoded
        absolute path (e.g. `read('/features/foo.json')`) that only makes
        sense inside that Docker layout. Setting `featuresMountPath = "/features"`
        with `featuresPath = "it/features"` makes `it/features` (resolved
        against the invoking shell's working directory) appear as `/features`
        to the JVM, without touching the real host `/features` (if any) and
        without copying anything into the Nix store.

        Leave `null` (the default) to run the JVM directly against
        `featuresPath`, with no remapping.

        On Linux: must be a real subpath (e.g. `/features`), not `/` itself --
        the sandbox works by building one fresh, writable root and
        re-binding `/nix`, `/dev`, `/proc`, `/etc`, `/run`, `/tmp` and the
        caller's working directory back onto it, so mounting something else
        directly onto `/` would hide those.

        On Darwin: there is no namespace-based sandbox equivalent to
        `bubblewrap`, so `bindfs` (a FUSE filesystem) is used instead, with
        two consequences: (1) it requires `macFUSE` to be installed and
        approved by the user once -- a system extension outside of Nix's
        control, this option cannot install or consent to it for you; (2)
        unlike the disposable Linux sandbox, `bindfs` mounts onto the *real*
        filesystem, so `featuresMountPath` must already exist as a directory
        the invoking user owns (e.g. created once with
        `sudo mkdir -p /features && sudo chown "$(whoami)" /features`) --
        evaluation succeeds either way, but the run fails at execution time
        with a clear message if the directory is missing. This Darwin path is
        less exercised than the Linux one; treat it as best-effort.
      '';
    };

    karateConfigDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = ".";
      description = ''
        Directory containing a custom `karate-config.js`, passed as
        `-Dkarate.config.dir=<dir>`. Resolved at runtime against the invoking
        shell's working directory. Leave `null` to use Karate's default
        resolution (classpath / current directory).
      '';
    };

    karateConfigMountPath = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/karate-config";
      description = ''
        Absolute path at which `karateConfigDir` should appear to the running
        JVM, bind-mounted at run time -- the same remapping Docker usage does
        with `-v <my-specific-karate-config.js>:/karate-config.js`.
        Implemented the same way as `featuresMountPath` (`bubblewrap` on
        Linux, `bindfs` on Darwin, with the same Darwin caveats: manual
        `macFUSE` setup, and the target directory must already exist and be
        owned by the invoking user).

        `karate-config.js` (or code it calls into) sometimes reads auxiliary
        files via a hardcoded absolute path that only makes sense inside that
        Docker layout, the same problem `featuresMountPath` solves for
        `featuresPath`. Setting `karateConfigMountPath = "/karate-config"`
        with `karateConfigDir = "it/config"` makes `it/config` (resolved
        against the invoking shell's working directory) appear as
        `/karate-config` to the JVM -- `-Dkarate.config.dir` is then set to
        the mounted path -- without touching the real host filesystem and
        without copying anything into the Nix store.

        Leave `null` (the default) to run the JVM directly against
        `karateConfigDir`, with no remapping. Requires `karateConfigDir` to
        also be set. Must be a real subpath (e.g. `/karate-config`), not `/`
        itself, for the same reason as `featuresMountPath`.
      '';
    };

    outputDir = mkOption {
      type = types.str;
      default = "target/karate-reports";
      description = "Report output directory, passed as `-o`.";
    };

    tags = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "@smoke";
      description = "Tag expression filter, passed as `-t`.";
    };

    threads = mkOption {
      type = types.ints.positive;
      default = 1;
      description = "Parallel thread count, passed as `-T`.";
    };

    format = mkOption {
      type = types.listOf types.str;
      default = [ "junit:xml" "cucumber:json" ];
      description = "Report formats, comma-joined and passed as `-f`.";
    };

    env = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "dev";
      description = "Karate environment name, passed as `-e` (`karate.env`).";
    };

    name = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Scenario name filter, passed as `-n`.";
    };

    environmentVariables = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        RABBITMQ_HOST = "localhost";
        KAFKA_BOOTSTRAP_SERVERS = "localhost:9092";
      };
      description = ''
        OS environment variables exported before running, e.g. the
        `RABBITMQ_*`/`KAFKA_*`/`SNOWFLAKE_*` variables read by
        karate-connect's extensions, or any variable a consumer's own
        `karate-config.js` relies on.
      '';
    };

    jvmArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "-Xmx2g" ];
      description = "Extra JVM arguments (e.g. heap size, custom system properties).";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Escape hatch: extra arguments appended verbatim to the Karate CLI invocation.";
    };

    extraClasspath = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "src/test/fixtures" ];
      description = ''
        Extra directories added to the JVM classpath alongside the JAR and
        `featuresPath`, resolved at runtime against the invoking shell's
        working directory. Needed when a feature reads a sibling resource via
        `classpath:...` (e.g. a mock JSON fixture) from outside
        `featuresPath`.
      '';
    };
  };

  config = { };
}
