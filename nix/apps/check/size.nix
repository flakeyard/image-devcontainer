{ pkgs, root, ... }:
{
  description = "Compare the image size with its budget";
  runtimeInputs = [ pkgs.gawk ];
  environment.IMAGE_LIB = "${root + "/scripts/lib/image.sh"}";
}
