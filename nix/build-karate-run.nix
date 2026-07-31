# Pure builder: turns one evaluated `karate-run-options.nix` config into a
# runnable wrapper script + a flake `app`. Shared by every adapter
# (flake-parts, plain `lib.mkKarateRun`, devenv) so their behavior never
# diverges.
#
# All path-like settings (featuresPath, karateConfigDir, outputDir,
# extraClasspath) are kept as plain strings and expanded by the wrapper *at
# run time*, so they resolve relative to the caller's current working
# directory (e.g. a consumer project's checkout) rather than being copied
# into the Nix store.
#
# The JAR is put on an explicit `-cp` (rather than run with `-jar`) together
# with `featuresPath`/`karateConfigDir`/`extraClasspath`, and
# `com.intuit.karate.Main` (the JAR's own `Main-Class`) is invoked directly.
# This is required so that `classpath:...` reads inside feature files (e.g.
# mock JSON fixtures colocated with the tests) can find files that live on
# disk next to the consumer's features rather than inside the JAR — `-jar`
# alone ignores any classpath entry besides the JAR itself.
{ pkgs, lib, name, cfg }:

let
  scriptName = "karate-run-${name}";

  quoted = s: lib.escapeShellArg s;

  # `cfg.featuresMountPath` mirrors Docker's `-v <features_path>:/features`:
  # some feature files read fixtures via a hardcoded absolute path that only
  # makes sense inside that Docker layout (e.g. `read('/features/foo.json')`).
  # When set, `bubblewrap` bind-mounts `cfg.featuresPath` onto that absolute
  # path for the JVM's mount namespace only -- no Nix store copy, no change
  # to the real filesystem outside the wrapped process.
  useFeaturesMount = cfg.featuresMountPath != null;

  # `featuresPath` as seen by the JVM: either the plain path, or the absolute
  # mount point it has been bind-mounted onto.
  effectiveFeaturesPath = if useFeaturesMount then cfg.featuresMountPath else cfg.featuresPath;

  envExports = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (k: v: "export ${k}=${quoted v}") cfg.environmentVariables
  );

  classpathEntries = lib.unique (
    [ "${cfg.jar}" effectiveFeaturesPath ]
    ++ lib.optional (cfg.karateConfigDir != null) cfg.karateConfigDir
    ++ cfg.extraClasspath
  );
  classpath = lib.concatStringsSep ":" classpathEntries;

  javaArgs = lib.concatStringsSep " " (
    [ "-Dextensions=${lib.concatStringsSep "," cfg.extensions}" ]
    ++ lib.optional (cfg.karateConfigDir != null) ''-Dkarate.config.dir="${cfg.karateConfigDir}"''
    ++ map quoted cfg.jvmArgs
  );

  karateArgs = lib.concatStringsSep " " (
    [ "-T" (toString cfg.threads) ]
    ++ [ "-o" (quoted cfg.outputDir) ]
    ++ [ "-f" (quoted (lib.concatStringsSep "," cfg.format)) ]
    ++ lib.optionals (cfg.tags != null) [ "-t" (quoted cfg.tags) ]
    ++ lib.optionals (cfg.env != null) [ "-e" (quoted cfg.env) ]
    ++ lib.optionals (cfg.name != null) [ "-n" (quoted cfg.name) ]
    ++ map quoted cfg.extraArgs
  );

  javaInvocation = ''java ${javaArgs} -cp "${classpath}" com.intuit.karate.Main ${karateArgs} "${effectiveFeaturesPath}"'';

  # Binding `featuresMountPath` directly under the *real* root (`--dev-bind /
  # /`) would require creating that mount point on the real host filesystem,
  # which fails with a permission error for any path the caller can't already
  # write to (e.g. `/features`). Instead, build a fresh, writable `tmpfs` root
  # for the sandbox and re-bind only what the JVM actually needs onto it:
  # `/nix` (the JDK/JAR themselves), `/dev`, `/proc`, the usual DNS/locale
  # config under `/etc` (and `/run`, since `/etc/resolv.conf` often symlinks
  # there), `/tmp`, and the caller's own working directory (so every other
  # relative path -- `outputDir`, `karateConfigDir`, `extraClasspath`, report
  # writes, ...) keeps resolving exactly as it would without the sandbox).
  # The environment (network namespace included) is otherwise left untouched,
  # so extensions talking to `localhost`/real hosts (RabbitMQ, Kafka, ...)
  # keep working unchanged.
  execLine =
    if useFeaturesMount
    then ''
      bwrapArgs=(--tmpfs / --ro-bind /nix /nix --dev /dev --proc /proc --bind /tmp /tmp)
      for d in /etc /run /var/run; do
        if [ -e "$d" ]; then
          bwrapArgs+=(--ro-bind "$d" "$d")
        fi
      done
      bwrapArgs+=(--bind "$PWD" "$PWD")
      bwrapArgs+=(--bind ${quoted cfg.featuresPath} ${quoted cfg.featuresMountPath})
      exec bwrap "''${bwrapArgs[@]}" -- ${javaInvocation}''
    else "exec ${javaInvocation}";

  wrapper = pkgs.writeShellApplication {
    name = scriptName;
    runtimeInputs = [ cfg.jdk ] ++ lib.optional useFeaturesMount pkgs.bubblewrap;
    text = ''
      ${envExports}

      ${execLine}
    '';
  };
in
lib.throwIf (useFeaturesMount && !pkgs.stdenv.isLinux)
  "karate-connect run '${name}': featuresMountPath requires bubblewrap, which is only available on Linux"
{
  package = wrapper;
  app = {
    type = "app";
    program = "${wrapper}/bin/${scriptName}";
    meta.description = "Run karate-connect Karate tests (run '${name}')";
  };
}
