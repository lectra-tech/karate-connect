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

  # Every path-like setting that can be bind-mounted onto an absolute
  # location for the JVM, mirroring Docker's `-v <host>:<container>` mapping
  # (e.g. `VOLUME /features`, or `-v <my-karate-config.js>:/karate-config.js`).
  # Feature files and `karate-config.js` (or code it calls into) sometimes
  # read auxiliary files via a hardcoded absolute path that only makes sense
  # inside that Docker layout. `bind` pairs are collected here so a single
  # `bubblewrap` invocation can perform every requested mapping at once.
  mounts = lib.filter (m: m.mountPath != null) [
    { hostPath = cfg.featuresPath; mountPath = cfg.featuresMountPath; option = "featuresMountPath"; }
    { hostPath = cfg.karateConfigDir; mountPath = cfg.karateConfigMountPath; option = "karateConfigMountPath"; }
  ];
  useMounts = mounts != [ ];

  # Each path as seen by the JVM: either the plain host path, or the absolute
  # mount point it has been bind-mounted onto.
  effectiveFeaturesPath = if cfg.featuresMountPath != null then cfg.featuresMountPath else cfg.featuresPath;
  effectiveKarateConfigDir = if cfg.karateConfigMountPath != null then cfg.karateConfigMountPath else cfg.karateConfigDir;

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

  javaInvocation = ''java ${javaArgs} -cp "${classpath}" com.intuit.karate.Main ${karateArgs} "${effectiveFeaturesPath}"'';

  # Linux: build a fresh, writable `tmpfs` root for the sandbox and re-bind
  # only what the JVM actually needs onto it: `/nix` (the JDK/JAR
  # themselves), `/dev`, `/proc`, the usual DNS/locale config under `/etc`
  # (and `/run`, since `/etc/resolv.conf` often symlinks there), `/tmp`, and
  # the caller's own working directory (so every other relative path --
  # `outputDir`, `extraClasspath`, report writes, ...) keeps resolving
  # exactly as it would without the sandbox). Every requested mapping is then
  # bind-mounted on top, in one `bubblewrap` invocation. Binding a mount
  # directly under the *real* root (`--dev-bind / /`) would instead require
  # creating that mount point on the real host filesystem, which fails with a
  # permission error for any path the caller can't already write to (e.g.
  # `/features`) -- hence the synthetic root. The environment (network
  # namespace included) is otherwise left untouched, so extensions talking to
  # `localhost`/real hosts (RabbitMQ, Kafka, ...) keep working unchanged.
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

  # macOS has no equivalent of Linux user/mount namespaces, so `bubblewrap`
  # cannot be used there. `bindfs` (a FUSE filesystem) is used instead to
  # perform the same bind-mount, but with two consequences the Linux path
  # doesn't have: (1) it requires `macFUSE` to be installed and approved by
  # the user once, outside of Nix's control (a kernel/system extension, not
  # something this wrapper can install or consent to on the user's behalf);
  # (2) unlike the disposable Linux sandbox, `bindfs` mounts onto the *real*
  # filesystem, so each `mountPath` must already exist as a directory the
  # invoking user owns (e.g. created once with
  # `sudo mkdir -p /features && sudo chown "$(whoami)" /features`) -- this
  # wrapper only checks for that and fails with a clear message otherwise, it
  # does not create top-level paths itself. Every mount is unmounted again
  # once the JVM exits (success or failure), via an `EXIT` trap; `exec` is
  # deliberately *not* used for the `java` invocation itself so that trap
  # still gets to run cleanup afterwards.
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

  execLine =
    if !useMounts then "exec ${javaInvocation}"
    else if pkgs.stdenv.isLinux then linuxExecLine
    else darwinExecLine;

  wrapper = pkgs.writeShellApplication {
    name = scriptName;
    runtimeInputs = [ cfg.jdk ]
      ++ lib.optional (useMounts && pkgs.stdenv.isLinux) pkgs.bubblewrap
      ++ lib.optional (useMounts && pkgs.stdenv.isDarwin) pkgs.bindfs;
    text = ''
      ${envExports}

      ${execLine}
    '';
  };
in
lib.throwIf (lib.any (m: m.hostPath == null) mounts)
  "karate-connect run '${name}': ${lib.concatMapStringsSep ", " (m: m.option) (lib.filter (m: m.hostPath == null) mounts)} set without its corresponding host path option (featuresPath/karateConfigDir)"
  (lib.throwIf (useMounts && !(pkgs.stdenv.isLinux || pkgs.stdenv.isDarwin))
    "karate-connect run '${name}': featuresMountPath/karateConfigMountPath require bubblewrap (Linux) or bindfs/macFUSE (Darwin), neither of which is available on this platform"
    (lib.throwIf (lib.any (m: m.mountPath == "/") mounts)
      "karate-connect run '${name}': featuresMountPath/karateConfigMountPath must be a real subpath, not \"/\" itself"
      {
        package = wrapper;
        app = {
          type = "app";
          program = "${wrapper}/bin/${scriptName}";
          meta.description = "Run karate-connect Karate tests (run '${name}')";
        };
      }))

