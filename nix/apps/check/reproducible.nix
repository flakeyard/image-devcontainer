{ pkgs, ... }:
{
  description = "Rebuild own derivations, compare two streams";
  runtimeInputs = [ pkgs.gawk ];
}
