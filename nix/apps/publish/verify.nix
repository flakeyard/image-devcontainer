{ pkgs, shellLib, ... }:
{
  description = "Check the published image of a release";
  runtimeInputs = with pkgs; [
    crane
    gh
    gnugrep
    jq
  ];
  environment.PUBLISH_LIB = "${../../../scripts/publish/lib.sh}";
  environment.SHELL_LIB = "${shellLib}";
}
