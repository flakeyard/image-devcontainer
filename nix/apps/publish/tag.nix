{ pkgs, ... }:
{
  description = "Set the release tag of the manifest list";
  runtimeInputs = with pkgs; [
    crane
    gnugrep
  ];
  environment.PUBLISH_LIB = "${../../../scripts/publish/lib.sh}";
}
