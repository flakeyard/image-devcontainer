# The entrypoint of the image, with the tools it runs.
{ pkgs, nix }:
let
  runtimeInputs = [
    nix
  ]
  ++ (with pkgs; [
    coreutils
    findutils
    gawk
    gnused
    util-linuxMinimal
    tini
  ]);
in
pkgs.writeShellApplication {
  name = "entrypoint";
  inherit runtimeInputs;
  # The tools on the fixed PATH of root's Nix processes, not the PATH the
  # container passes.
  text = ''
    entrypoint_tools=${pkgs.lib.makeBinPath runtimeInputs}
  ''
  + builtins.readFile ../entrypoint/entrypoint.sh;
}
