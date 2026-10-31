# The image (FY-0005): a script that streams it as a docker archive.
{ pkgs, parts }:
let
  inherit (pkgs) lib;
  inherit (parts) users;
  homeRel = lib.removePrefix "/" users.home;
  foreign = import ./foreign.nix { inherit pkgs; };
  # The image's Nix writes the store database of the image.
  dockerTools = pkgs.dockerTools.override { inherit (parts) nix; };

  # Store paths the image uses outside `contents`, through links and settings.
  # In `contents` they are garbage collection roots of the image's store.
  roots = pkgs.linkFarm "image-roots" (
    map (path: {
      # The name only; `path` keeps the dependency.
      name = builtins.unsafeDiscardStringContext (baseNameOf path);
      inherit path;
    }) (lib.unique ([ parts.entrypoint ] ++ foreign.paths))
  );

  contents = parts.tools ++ [
    roots
    dockerTools.binSh
    dockerTools.usrBinEnv
  ];

  bashrc = ''
    # Interactive shells enter project shells through direnv.
    [ -n "$PS1" ] || return
    eval "$(direnv hook bash)"
    PS1='\u@devcontainer:\w\$ '
  '';

  env = [
    "LANG=C.UTF-8"
    "PATH=${users.home}/.nix-profile/bin:/bin:/usr/bin"
    "TZDIR=${pkgs.tzdata}/share/zoneinfo"
    "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
    "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
    "NIX_REMOTE=daemon"
    "NIX_LD=${pkgs.stdenv.cc.bintools.dynamicLinker}"
    "NIX_LD_LIBRARY_PATH=${foreign.libraryPath}"
  ];

  metadata = builtins.toJSON [
    {
      remoteUser = users.user;
      overrideCommand = false;
      init = true;
      updateRemoteUserUID = true;
    }
  ];
in
dockerTools.streamLayeredImage {
  name = "image-devcontainer";
  # Not a registry tag: the release workflow publishes by digest.
  tag = "build";
  maxLayers = 100;
  includeNixDB = true;
  inherit contents;

  passthru = {
    # Refers to every path in `contents`: its closure is the image's store,
    # which the SBOM describes.
    closureRoot = pkgs.writeText "image-closure-root" (lib.concatMapStringsSep "\n" toString contents);
    # What the smoke tests expect of the image.
    expected = pkgs.linkFarm "image-expected" {
      "nix.conf" = pkgs.writeText "nix.conf" parts.nixConf;
      "env" = pkgs.writeText "env" (lib.concatLines env);
      "metadata" = pkgs.writeText "metadata" metadata;
      "nix-version" = pkgs.writeText "nix-version" parts.nix.version;
      # The library directories nix-ld serves besides glibc.
      "foreign-libraries" = pkgs.writeText "foreign-libraries" (
        lib.concatMapStrings (l: "${lib.getLib l}/lib\n") foreign.libraries
      );
    };
  };

  extraCommands = ''
    mkdir -p etc/nix etc/ssl/certs tmp root var/empty var/log ${homeRel}/.config/direnv
    chmod 1777 tmp

    # Regular files, not links into the store: tools edit them in place.
    rm -f etc/passwd etc/group etc/nix/nix.conf etc/profile.d/nix.sh etc/profile.d/nix-daemon.sh
    cp ${pkgs.writeText "passwd" users.passwd} etc/passwd
    cp ${pkgs.writeText "group" users.group} etc/group
    cp ${pkgs.writeText "nix.conf" parts.nixConf} etc/nix/nix.conf
    cp ${pkgs.writeText "bashrc" bashrc} etc/bashrc
    chmod 644 etc/passwd etc/group etc/nix/nix.conf etc/bashrc
    # Login shells get the same setup.
    echo '[ -f /etc/bashrc ] && . /etc/bashrc' > etc/profile
    printf 'passwd: files\ngroup: files\nhosts: files dns\n' > etc/nsswitch.conf
    printf '%s\n' 'NAME="flakeyard devcontainer"' 'ID=flakeyard' 'ID_LIKE=nixos' \
      'PRETTY_NAME="flakeyard devcontainer"' > etc/os-release
    ln -s ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt etc/ssl/certs/ca-certificates.crt
    ${foreign.links}
    echo 'source ${parts.nix-direnv}/share/nix-direnv/direnvrc' > ${homeRel}/.config/direnv/direnvrc
  '';

  fakeRootCommands = ''
    chown -R ${toString users.uid}:${toString users.uid} ${homeRel}
    # Build users must not read the developer's files.
    chmod 750 ${homeRel}
  '';

  config = {
    # Starts as root to run the Nix daemon, then switches to dev.
    User = "0:0";
    Entrypoint = [ (lib.getExe parts.entrypoint) ];
    Cmd = [
      "${pkgs.coreutils}/bin/sleep"
      "infinity"
    ];
    WorkingDir = users.home;
    Env = env;
    # The same for every commit; version and commit are annotations of the
    # manifest list (FY-0027).
    Labels = {
      "devcontainer.metadata" = metadata;
      "org.opencontainers.image.source" = "https://github.com/flakeyard/image-devcontainer";
      "org.opencontainers.image.description" =
        "Dev container image with multi-user Nix, direnv and nix-direnv";
      "org.opencontainers.image.licenses" = "MIT";
    };
  };
}
