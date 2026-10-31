# Weekly maintenance, not required (FY-0027).
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
