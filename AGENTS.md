# AGENTS.md

Instructions for coding agents working on `karate-connect`.

## Overview

`karate-connect` packages [Karate Core](https://github.com/karatelabs/karate) plus **extensions**
(`base`, `rabbitmq`, `kafka`, `snowflake`, `dbt`, `kubernetes`) into a fat JAR
(`karate-connect-<version>-standalone.jar`, main class `com.intuit.karate.Main`) and a set of Docker images.

An extension is a folder under `src/main/resources/<extension>/` combining Karate feature files,
a `karate-ext-config.js`, and optionally Kotlin helper classes.

Stack: Kotlin/JVM (toolchain 21), Gradle Kotlin DSL, JUnit 5, Docker Compose, Python (Snowflake CLI & dbt).

## Project layout

```
build.gradle.kts                       # build, fat JAR, extension JS code generation
gradle/libs.versions.toml              # version catalog (all dependency versions live here)
compose.yml + Dockerfile_*             # builder -> minimal -> python -> nominal / aks images
devenv.nix / devenv.yaml               # optional Nix dev environment (devenv.sh)
flake.nix + nix/*.nix                  # optional Nix module for consumers to run Karate tests
entrypoint.sh                          # Docker entrypoint (KARATE_EXTENSIONS -> -Dextensions)
docs/headers/                          # license header templates + add-headers.sh
src/main/kotlin/com/lectra/karate/connect/
    Extension.kt                       # enum of supported extensions
    BrokerClient.kt, rabbitmq/, kafka/ # Kotlin clients called from features
src/main/resources/
    karate-base.js                     # `base` extension, always loaded
    <extension>/karate-ext-config.js   # extension config, exposed as `<extension>.<key>`
    <extension>/*.feature              # extension API (see below)
src/test/resources/
    karate-config.js                   # test-side config (e.g. Snowflake PEM init)
    <extension>/*.test.feature         # integration tests
src/test/kotlin/com/lectra/karate/connect/
    AllFeaturesTest.kt                 # JUnit 5 runner, parallel(16)
    LocalBroker.kt, kafka/, rabbitmq/  # embedded brokers for tests
```

## Build & test commands

```bash
source .envrc                      # creates py_venv, installs requirements.txt (or: direnv allow)
./gradlew build                    # fat JAR + all tests
./gradlew build -DtestExtensions=rabbitmq,kafka,kubernetes   # default subset, skips Snowflake/dbt
./gradlew test --tests '*AllFeaturesTest*'                   # tests only
./gradlew karateVersion            # prints the Karate version in use
docker compose build               # builds all 5 local images
```

- `-DtestExtensions` (default `rabbitmq,kafka,kubernetes`) selects which extensions are exercised.
  Use it whenever no Snowflake account is configured — Snowflake/dbt tests will otherwise fail.
- Tests are always re-run (`outputs.upToDateWhen { false }`).
- The project version comes from `git describe --tags` (grgit), so a shallow clone without tags yields `0.0.0`.

### Optional: devenv

[devenv](https://devenv.sh) provides the whole toolchain (JDK 21, Python CLIs, `kubectl`) without
installing anything system-wide. It is opt-in and does not interfere with `.envrc`/`py_venv`.

```bash
devenv shell   # toolchain + kc-build / kc-build-all / kc-test / kc-docker-build / kc-headers
devenv test    # fat JAR + tests on $TEST_EXTENSIONS
```

It uses a project-local `GRADLE_USER_HOME` (under `.devenv/state/`) and clears the extension
environment variables (`KAFKA_*`, `RABBITMQ_*`, `SNOWFLAKE_*`), which the `configFromEnv` test
scenarios require to be unset. Docker is not provided: `kc-docker-build` uses the host daemon.

### Optional: `flake.nix` — reusable Nix module for consumers

`flake.nix` + `nix/*.nix` let **other** Nix projects import karate-connect and run its Karate CLI
against their own features, with every setting customizable (extensions, features path,
`karate-config.js` location, tags, threads, output format, environment variables, JVM args). This is
for consumers of karate-connect, not for building karate-connect itself (which is still done with
Gradle as above).

- The JAR is **fetched from a pinned GitHub Release** (`nix/default-jar.nix`, `fetchurl` +
  content hash) — it is not rebuilt from source by Nix.
- `nix/karate-run-options.nix` is the single shared option set (submodule); `nix/build-karate-run.nix`
  turns one evaluated config into a `writeShellApplication` wrapper that invokes
  `com.intuit.karate.Main` with `-cp "<jar>:<featuresPath>:<karateConfigDir>:<extraClasspath>"`
  (not `-jar`, so that `classpath:...` reads inside features can find files on disk next to the
  consumer's own feature/config directories).
- Three adapters wrap that same core, so behavior never diverges:
  - `flakeModules.default` — flake-parts module: `perSystem.karate-connect.runs.<name>` →
    `packages`/`apps` named `karate-test-<name>`.
  - `lib.mkKarateRun` — plain function (`lib.evalModules` under the hood) for consumers without
    flake-parts.
  - `devenvModules.default` — devenv module: `karate-connect.runs.<name>` → a `karate-<name>` script.
- This repo dogfoods the module itself: `checks.kubernetes-smoke` (`nix flake check`) runs the
  `kubernetes` extension against the existing **mocked** `cronJob.test.feature` — fully offline,
  no `kubectl`/network needed — proving the fetch → wrapper → Karate run chain end-to-end.

```bash
nix run .#karate-test-kubernetes-smoke   # this repo's own dogfood run
nix flake check                          # includes the same run as checks.kubernetes-smoke
```

## How extensions work (important)

`processResources` in `build.gradle.kts` walks every directory under `src/main/resources/` and
**generates `<extension>/<extension>.js`** from the feature files it finds. Each scenario becomes a
callable function:

```gherkin
* def result = <extension>.<featureFile>.<scenarioName>(args)
```

Consequences:

- **A scenario name is public API.** Renaming a scenario is a breaking change.
- Scenarios tagged `@ignore` and features tagged `@deprecated` are excluded from generation;
  `Scenario Outline` sections are ignored too.
- The generated `<extension>.js` is a build artifact under `build/resources/main/`. Never commit or
  hand-edit it; regenerate with `./gradlew processResources`.
- Adding an extension = create `src/main/resources/<name>/` **and** add `<name>` to the
  `Extension` enum in `Extension.kt`, plus tests in `src/test/resources/<name>/`.

At runtime, `karate-base.js` reads `karate.properties["extensions"]` and loads
`classpath:<ext>/karate-ext-config.js` for each one; its returned object is exposed as `<ext>.<key>`.
A missing extension is only logged, never fatal.

## Conventions

- **License headers are mandatory.** Every `.kt` and `.js` file starts with the star header, every
  `.feature` with the sharp header (`docs/headers/*-header-comment.txt`). Run
  `docs/headers/add-headers.sh` after adding files; it rewrites headers in place. Markdown/AsciiDoc
  files are not headered.
- **Feature files** follow a fixed shape: `@ignore` on the `Feature:` line, one tag per scenario
  matching the scenario name, an `args: { ... }` comment documenting the payload, and a result of
  the form `json result = { status: "OK", data }` (`"FAILED"` on error).
- Optional arguments are read with `karate.get("name", default)`.
- **Dependencies** are declared only in `gradle/libs.versions.toml` (Renovate keeps them updated);
  never hardcode versions in `build.gradle.kts`.
- **Commits**: conventional commit messages (`fix:`, `feat:`, `chore:`, `doc:`) and a DCO sign-off is
  required — `git commit -s`. See `CONTRIBUTING.adoc`.

## Gotchas

- Snowflake and dbt tests need `src/test/resources/snowflake/snowflake.properties` (gitignored,
  see `snowflake.template.properties`). **Never commit credentials** or create that file with real values.
- Kafka and RabbitMQ tests run against embedded brokers started by `AllFeaturesTest`; no external
  service is required for them.
- The `base` extension is always loaded; the others are enabled via `-Dextensions=...`
  (or `KARATE_EXTENSIONS` in Docker).
- `build/`, `py_venv/`, `target/`, `*.jar` and `snowflake.properties` are gitignored — don't add them.
- Any change to a public extension API (scenario names, config keys, arguments) must be reflected in
  the corresponding section of `README.adoc`.
