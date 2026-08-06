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

  platform =
    if pkgs.stdenv.isLinux then "linux"
    else if pkgs.stdenv.isDarwin then "darwin"
    else "unsupported";

  ## -- 1. Bind-mount settings & validation -----------------------------------
  # Every path-like setting that can be bind-mounted onto an absolute location
  # for the JVM, mirroring Docker's `-v <host>:<container>` mapping. See
  # `featuresMountPath`/`karateConfigMountPath` in karate-run-options.nix for
  # the full rationale, platform support and caveats.
  mounts = lib.filter (m: m.mountPath != null) [
    { hostPath = cfg.featuresPath; mountPath = cfg.featuresMountPath; option = "featuresMountPath"; }
    { hostPath = cfg.karateConfigDir; mountPath = cfg.karateConfigMountPath; option = "karateConfigMountPath"; }
  ];
  useMounts = mounts != [ ];

  missingHostPath = lib.filter (m: m.hostPath == null) mounts;

  # Collected up front so evaluation fails once, with every problem reported
  # together, instead of nested `throwIf`s wrapping the final result.
  errors =
    lib.optional (missingHostPath != [ ])
      "karate-connect run '${name}': ${lib.concatMapStringsSep ", " (m: m.option) missingHostPath} set without its corresponding host path option (featuresPath/karateConfigDir)"
    ++ lib.optional (useMounts && platform == "unsupported")
      "karate-connect run '${name}': featuresMountPath/karateConfigMountPath require bubblewrap (Linux) or bindfs/macFUSE (Darwin), neither of which is available on this platform"
    ++ lib.optional (lib.any (m: m.mountPath == "/") mounts)
      "karate-connect run '${name}': featuresMountPath/karateConfigMountPath must be a real subpath, not \"/\" itself";

  ## -- 2. Effective paths, as seen by the JVM --------------------------------
  # Either the plain host path, or the absolute mount point it has been
  # bind-mounted onto.
  effectivePath = hostPath: mountPath: if mountPath != null then mountPath else hostPath;
  effectiveFeaturesPath = effectivePath cfg.featuresPath cfg.featuresMountPath;
  effectiveKarateConfigDir = effectivePath cfg.karateConfigDir cfg.karateConfigMountPath;

  ## -- 3. Classpath, JVM & Karate CLI arguments -------------------------------
  envExports = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (k: v: "export ${k}=${quoted v}") cfg.environmentVariables
  );

  classpathEntries = lib.unique (
    [ "${cfg.jar}" effectiveFeaturesPath ]
    ++ lib.optional (effectiveKarateConfigDir != null) effectiveKarateConfigDir
    ++ cfg.extraClasspath
  );
  classpath = lib.concatStringsSep ":" classpathEntries;

  javaArgs = lib.concatStringsSep " " (
    [ "-Dextensions=${lib.concatStringsSep "," cfg.extensions}" ]
    ++ lib.optional (effectiveKarateConfigDir != null) ''-Dkarate.config.dir="${effectiveKarateConfigDir}"''
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

  # Mirrors the Docker image's own `entrypoint.sh` (`java ... $@`, with
  # `CMD ["features"]` as the default): calling the wrapper with no arguments
  # runs the configured `featuresPath` (or its mount-mapped equivalent), and
  # calling it with one or more arguments (e.g. `karate-default
  # src/test/features/foo.feature`) replaces it entirely -- only the given
  # path(s) run, exactly like `docker run <image> <args>` overrides `CMD`
  # rather than adding to it. `classpath` is unaffected either way, so
  # `classpath:...`-relative resource resolution keeps working even when a
  # single feature file outside `featuresPath` is targeted.
  featureArgsSnippet = ''
    if [ "$#" -gt 0 ]; then
      featureArgs=("$@")
    else
      featureArgs=(${quoted effectiveFeaturesPath})
    fi
  '';

  javaInvocation = ''java ${javaArgs} -cp "${classpath}" com.intuit.karate.Main ${karateArgs} "''${featureArgs[@]}"'';

  ## -- 4. Platform-specific exec line -----------------------------------------
  # Builds a fresh, writable sandbox root and re-binds only what the JVM
  # needs (`/nix`, `/dev`, `/proc`, `/etc`/`/run`, `/tmp`, and the caller's
  # working directory) before bind-mounting every requested mapping on top,
  # in one `bubblewrap` invocation. See `featuresMountPath` in
  # karate-run-options.nix for the full rationale and caveats.
  linuxExecLine = ''
    bwrapArgs=(--tmpfs / --ro-bind /nix /nix --dev /dev --proc /proc --bind /tmp /tmp)
    for d in /etc /run /var/run; do
      if [ -e "$d" ]; then
        bwrapArgs+=(--ro-bind "$d" "$d")
      fi
    done
    bwrapArgs+=(--bind "$PWD" "$PWD")
    ${lib.concatMapStringsSep "\n    " (m: "bwrapArgs+=(--bind ${quoted m.hostPath} ${quoted m.mountPath})") mounts}
    exec bwrap "''${bwrapArgs[@]}" -- ${javaInvocation}'';

  # No Linux-style sandbox exists on Darwin, so `bindfs` (a FUSE filesystem)
  # performs the same bind-mount directly on the real filesystem instead.
  # Each `mountPath` must already exist and be owned by the invoking user
  # (checked below, with a clear error otherwise); mounts are undone via an
  # `EXIT` trap, so `exec` is deliberately *not* used for the `java`
  # invocation itself. See `featuresMountPath` in karate-run-options.nix for
  # the full rationale and caveats.
  darwinExecLine = ''
    cleanup() {
      ${lib.concatMapStringsSep "\n      " (m: ''umount ${quoted m.mountPath} >/dev/null 2>&1 || true'') (lib.reverseList mounts)}
    }
    trap cleanup EXIT

    ${lib.concatMapStringsSep "\n    " (m: ''
      if [ ! -d ${quoted m.mountPath} ]; then
        echo "karate-connect: ${quoted m.mountPath} does not exist -- pre-create it once, e.g.:" >&2
        echo "  sudo mkdir -p ${quoted m.mountPath} && sudo chown \"\$(whoami)\" ${quoted m.mountPath}" >&2
        exit 1
      fi
      bindfs ${quoted m.hostPath} ${quoted m.mountPath}'') mounts}

    ${javaInvocation}'';

  platformExecLine = if platform == "linux" then linuxExecLine else darwinExecLine;
  execLine = if useMounts then platformExecLine else "exec ${javaInvocation}";

  ## -- 5. Wrapper derivation ---------------------------------------------------
  package = pkgs.writeShellApplication {
    name = scriptName;
    runtimeInputs = [ cfg.jdk ]
      ++ lib.optional (useMounts && platform == "linux") pkgs.bubblewrap
      ++ lib.optional (useMounts && platform == "darwin") pkgs.bindfs;
    text = ''
      ${envExports}

      ${featureArgsSnippet}
      ${execLine}
    '';
  };
in
if errors != [ ] then
  throw (lib.concatStringsSep "\n" errors)
else
  {
    inherit package;
    app = {
      type = "app";
      program = "${package}/bin/${scriptName}";
      meta.description = "Run karate-connect Karate tests (run '${name}')";
    };
  }

