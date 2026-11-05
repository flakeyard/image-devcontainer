{ pkgs, ... }:
{
  description = "Publish the manifest list and its release tag";
  runtimeInputs = with pkgs; [
    crane
    gnugrep
    jq
    regclient
  ];
  environment.PUBLISH_LIB = "${../../../scripts/publish/lib.sh}";
}
