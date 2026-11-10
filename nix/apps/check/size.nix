{ pkgs, ... }:
{
  description = "Compare the image size with its budget";
  runtimeInputs = [ pkgs.gawk ];
  environment.IMAGE_LIB = "${../../../scripts/lib/image.sh}";
}
