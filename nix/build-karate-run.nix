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

  envExports = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (k: v: "export ${k}=${quoted v}") cfg.environmentVariables
  );

  classpathEntries = lib.unique (
    [ "${cfg.jar}" cfg.featuresPath ]
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

  wrapper = pkgs.writeShellApplication {
    name = scriptName;
    runtimeInputs = [ cfg.jdk ];
    text = ''
      ${envExports}

      exec java ${javaArgs} -cp "${classpath}" com.intuit.karate.Main ${karateArgs} "${cfg.featuresPath}"
    '';
  };
in
{
  package = wrapper;
  app = {
    type = "app";
    program = "${wrapper}/bin/${scriptName}";
    meta.description = "Run karate-connect Karate tests (run '${name}')";
  };
}
