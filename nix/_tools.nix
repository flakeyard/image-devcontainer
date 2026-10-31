# The tools of the image by name, part of its public API (FY-0005): Nix,
# direnv and nix-direnv, bash, and what a shell needs before a project shell
# exists. No toolchains, editors or other shells.
{
  pkgs,
  nix,
  nix-direnv,
}:
[
  nix
  nix-direnv
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
  openssh
  cacert
  tzdata
  iana-etc
  tini
])
