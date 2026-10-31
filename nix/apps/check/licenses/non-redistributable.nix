# Identifiers of the licenses in nixpkgs that forbid redistribution.
{ pkgs }:
let
  inherit (pkgs) lib;
in
pkgs.writeText "non-redistributable-licenses" (
  lib.concatLines (
    lib.concatMap (
      license:
      # sbomnix names a license by its SPDX id or short name.
      lib.filter (id: id != null) [
        (license.spdxId or null)
        (license.shortName or null)
      ]
    ) (lib.filter (license: !(license.redistributable or true)) (lib.attrValues lib.licenses))
  )
)
