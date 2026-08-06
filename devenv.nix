{ pkgs, lib, config, ... }:

let
  # Every environment variable read by an extension's `configFromEnv`. The
  # `*.test.feature` config scenarios assert that these resolve to null, so any
  # value inherited from the developer's shell makes the test suite fail. They
  # are cleared when entering the shell to keep local runs reproducible.
  extensionEnvVars = [
    "KAFKA_BOOTSTRAP_SERVERS"
    "KAFKA_KARATE_CONNECT_CONSUMER_GROUP_ID_PREFIX"
    "KAFKA_PASSWORD"
    "KAFKA_SASL_MECHANISM"
    "KAFKA_SCHEMA_REGISTRY_BASIC_AUTH_CREDENTIALS_SOURCE"
    "KAFKA_SCHEMA_REGISTRY_KEY"
    "KAFKA_SCHEMA_REGISTRY_SECRET"
    "KAFKA_SCHEMA_REGISTRY_URL"
    "KAFKA_SECURITY_PROTOCOL"
    "KAFKA_USERNAME"
    "PRIVATE_KEY_PASSPHRASE"
    "RABBITMQ_HOST"
    "RABBITMQ_PASSWORD"
    "RABBITMQ_PORT"
    "RABBITMQ_SSL"
    "RABBITMQ_USERNAME"
    "RABBITMQ_VIRTUAL_HOST"
    "SNOWFLAKE_ACCOUNT"
    "SNOWFLAKE_DATABASE"
    "SNOWFLAKE_PRIVATE_KEY_PATH"
    "SNOWFLAKE_ROLE"
    "SNOWFLAKE_SCHEMA"
    "SNOWFLAKE_USER"
    "SNOWFLAKE_WAREHOUSE"
  ];

  clearExtensionEnv = ''
    cleared=""
    for var in ${lib.concatStringsSep " " extensionEnvVars}; do
      if [ -n "''${!var:-}" ]; then
        cleared="$cleared $var"
        unset "$var"
      fi
    done
  '';
in
{
  # ---------------------------------------------------------------------------
  # Toolchain
  # ---------------------------------------------------------------------------

  # JDK 21, same major version as the Docker builder image (eclipse-temurin:21)
  # and as the Gradle toolchain declared in build.gradle.kts.
  # This also exports JAVA_HOME, which Gradle toolchain resolution relies on.
  languages.java.enable = true;
  languages.java.jdk.package = pkgs.temurin-bin-21;

  # Python 3.12 backs the `snowflake` and `dbt` extensions, which shell out to
  # the `snow` and `dbt` CLIs. It is pinned because those CLIs do not support
  # the current nixpkgs default interpreter yet.
  languages.python.enable = true;
  languages.python.package = pkgs.python312;

  packages = with pkgs; [
    # pipx installs the Python CLIs, see the task below. Checks are disabled
    # because the upstream test suite currently fails to build in nixpkgs.
    (pipx.overridePythonAttrs (_: {
      doCheck = false;
      doInstallCheck = false;
    }))
    kubectl # `kubernetes` extension
    git # grgit / release versioning
    openssl # Snowflake private key handling
    jq
  ];

  # ---------------------------------------------------------------------------
  # Environment
  # ---------------------------------------------------------------------------

  # Project-local Gradle home: keeps the build reproducible and immune to
  # host-wide ~/.gradle/init.d scripts (e.g. corporate repository mirrors).
  env.GRADLE_USER_HOME = "${config.env.DEVENV_STATE}/gradle";

  # Extensions exercised by the test suite. Snowflake and dbt are excluded by
  # default because they need real credentials, see the note in enterShell.
  env.TEST_EXTENSIONS = lib.mkDefault "rabbitmq,kafka,kubernetes";

  env.PIPX_HOME = "${config.env.DEVENV_STATE}/pipx";
  env.PIPX_BIN_DIR = "${config.env.DEVENV_STATE}/pipx/bin";
  env.PIPX_DEFAULT_PYTHON = "${pkgs.python312}/bin/python3";

  # The Snowflake connector loads manylinux wheels (pyarrow) that link against
  # libstdc++ / zlib, which are not on the default library path under Nix.
  env.LD_LIBRARY_PATH = lib.makeLibraryPath [
    pkgs.stdenv.cc.cc.lib
    pkgs.zlib
  ];

  # `.env` only carries Docker Compose settings, which Compose reads by itself.
  dotenv.disableHint = true;

  # ---------------------------------------------------------------------------
  # Python CLIs
  # ---------------------------------------------------------------------------

  # snowflake-cli and dbt-snowflake have conflicting transitive dependencies
  # (protobuf) and cannot share a single virtualenv, which is why the Docker
  # images install them with `pipx install --include-deps`. Same thing here:
  # one isolated environment per tool, requirements.txt staying the single
  # source of truth for the versions. `--include-deps` also exposes the entry
  # points of the dependencies, which is how `dbt` (from dbt-core) shows up.
  tasks."karate-connect:pythonCli" = {
    description = "Install the snowflake & dbt CLIs from requirements.txt";
    exec = ''
      set -euo pipefail
      mkdir -p "$PIPX_BIN_DIR"
      # shellcheck disable=SC2046
      pipx install --include-deps --force $(xargs < "$DEVENV_ROOT/requirements.txt")
    '';
    execIfModified = [ "requirements.txt" ];
    before = [ "devenv:enterShell" ];
  };

  # ---------------------------------------------------------------------------
  # Scripts
  # ---------------------------------------------------------------------------

  scripts.kc-build.exec = ''
    exec ./gradlew build -DtestExtensions="$TEST_EXTENSIONS" "$@"
  '';

  scripts.kc-build-all.exec = ''
    exec ./gradlew build -DtestExtensions=base,rabbitmq,kafka,snowflake,dbt,kubernetes "$@"
  '';

  scripts.kc-test.exec = ''
    exec ./gradlew test -DtestExtensions="$TEST_EXTENSIONS" "$@"
  '';

  scripts.kc-docker-build.exec = ''
    exec docker compose build "$@"
  '';

  scripts.kc-headers.exec = ''
    exec ./docs/headers/add-headers.sh "$@"
  '';

  # ---------------------------------------------------------------------------
  # Hooks
  # ---------------------------------------------------------------------------

  enterShell = ''
    export PATH="$PIPX_BIN_DIR:$PATH"

    ${clearExtensionEnv}

    echo "karate-connect dev environment"
    echo "  java : $(java -version 2>&1 | head -1)"
    echo "  snow : $(snow --version 2>/dev/null || echo 'n/a')"
    echo "  dbt  : $(dbt --version 2>/dev/null | head -1 || echo 'n/a')"
    echo ""
    echo "  kc-build        fat JAR + tests on \$TEST_EXTENSIONS ($TEST_EXTENSIONS)"
    echo "  kc-build-all    fat JAR + tests on every extension (Snowflake credentials required)"
    echo "  kc-test         tests only"
    echo "  kc-docker-build build the Docker images (uses the host Docker daemon)"
    echo "  kc-headers      re-apply the license headers"
    echo ""
    if [ -n "$cleared" ]; then
      echo "note: cleared inherited extension variables, which the config tests"
      echo "      expect to be unset:$cleared"
      echo ""
    fi
    if [ ! -f "$DEVENV_ROOT/src/test/resources/snowflake/snowflake.properties" ]; then
      echo "note: src/test/resources/snowflake/snowflake.properties is missing, so the"
      echo "      snowflake & dbt tests are skipped (TEST_EXTENSIONS=$TEST_EXTENSIONS)."
      echo "      See src/test/resources/snowflake/snowflake.template.properties."
      echo ""
    fi
    unset cleared
  '';

  # `devenv test` runs the same check as CI: fat JAR + Karate integration tests.
  enterTest = ''
    export PATH="$PIPX_BIN_DIR:$PATH"
    ${clearExtensionEnv}
    ./gradlew build -DtestExtensions="$TEST_EXTENSIONS"
  '';
}
