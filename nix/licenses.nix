# Licenses of image components that sbomnix cannot match with nixpkgs by
# name, taken from the metadata of the packages they come from. The SBOM is
# completed with them; check-licenses fails on any other component without a
# license, so a new one is added here on purpose.
{ pkgs, parts }:
let
  inherit (pkgs) lib;
  ids =
    package:
    map (license: license.spdxId or license.shortName) (
      lib.toList (package.meta.license or (throw "${package.name} has no meta.license"))
    );
  # The Nix package is a wrapper without a license; its libraries have one.
  nixLibrary = parts.nix.passthru.libs.nix-util or pkgs.nixVersions.nixComponents_2_35.nix-util;
  # Libraries of the Nix package, built separately.
  nixComponents = [
    "nix-cmd"
    "nix-expr"
    "nix-fetchers"
    "nix-flake"
    "nix-main"
    "nix-nswrapper"
    "nix-store"
    "nix-util"
  ];
in
lib.genAttrs nixComponents (_: ids nixLibrary)
// {
  # Our own derivations: the entrypoint and the links that keep paths alive.
  entrypoint = [ lib.licenses.mit.spdxId ];
  image-roots = [ lib.licenses.mit.spdxId ];
  # Links to bash and env made by dockerTools.
  bin-sh = ids pkgs.bashInteractive;
  usr-bin-env = ids pkgs.coreutils;
  # Outputs of glibc, gcc and icu under other names.
  getent-glibc = ids pkgs.glibc;
  xgcc = ids pkgs.stdenv.cc.cc;
  icu4c = ids pkgs.icu;
}
