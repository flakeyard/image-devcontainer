{ pkgs, ... }:
{
  description = "Point vX at the newest release of major X";
  runtimeInputs = with pkgs; [
    crane
    gnugrep
  ];
}
