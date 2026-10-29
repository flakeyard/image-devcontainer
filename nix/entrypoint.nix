# The entrypoint of the image, with the tools it runs.
{ pkgs, nix }:
pkgs.writeShellApplication {
  name = "entrypoint";
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
  text = builtins.readFile ../entrypoint/entrypoint.sh;
}
