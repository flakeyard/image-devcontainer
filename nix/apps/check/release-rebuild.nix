# Weekly, in the job rebuild of test.yaml (FY-0032).
{ pkgs, ... }:
{
  description = "Rebuild the newest release and compare";
  runtimeInputs = with pkgs; [
    crane
    git
    gnugrep
    jq
  ];
}
