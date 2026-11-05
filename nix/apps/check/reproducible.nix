{ pkgs, ... }:
{
  description = "Rebuild own derivations, compare two streams";
  runtimeInputs = [ pkgs.gawk ];
  environment.IMAGE_LIB = "${../../../scripts/lib/image.sh}";
}
