# The parts of the image that are plain data: its Nix, tools, users and Nix
# settings. Everything that builds the image takes them from here.
{ pkgs }:
let
  inherit (pkgs) lib;

  # The Nix of the image: the minor version of action-setup-nix (FY-0009).
  nix = pkgs.nixVersions.nix_2_35;
  # nix-direnv falls back to its own nix; it must be the image's.
  nix-direnv = pkgs.nix-direnv.override { inherit nix; };

  users = import ./users.nix { inherit lib; };
in
{
  inherit nix nix-direnv users;
  entrypoint = import ./entrypoint.nix { inherit pkgs nix; };
  tools = import ./tools.nix { inherit pkgs nix nix-direnv; };
  nixConf = import ./nix-conf.nix { inherit users; };
}
