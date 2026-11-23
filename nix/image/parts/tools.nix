# The tools of the image by name, part of its public API (ADR-0001): Nix,
# direnv and nix-direnv, bash, what a shell needs before a project shell
# exists, and devcontainer-setup (ADR-0002). No toolchains, editors, other
# shells or servers.
{
  perSystem =
    { config, pkgs, ... }:
    let
      inherit (config.image.parts)
        devcontainer-setup
        nix
        nix-direnv
        openssh-client
        tini
        ;
    in
    {
      image.parts.tools = [
        devcontainer-setup
        nix
        nix-direnv
        openssh-client
        tini
      ]
      ++ (with pkgs; [
        direnv
        bashInteractive
        coreutils
        findutils
        diffutils
        gnugrep
        gnused
        gawk
        gnutar
        gzip
        xz
        bzip2
        zstd
        less
        procps
        which
        util-linuxMinimal
        getent
        curl
        gitMinimal
        cacert
        tzdata
        iana-etc
      ]);
    };
}
