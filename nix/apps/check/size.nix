{ pkgs, ... }:
{
  description = "Compare the image size with its budget";
  runtimeInputs = [ pkgs.gawk ];
}
