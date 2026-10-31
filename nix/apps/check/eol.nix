# Weekly maintenance, not required (FY-0026).
{ pkgs, ... }:
{
  description = "Warn before the nixpkgs branch reaches its end of life";
  runtimeInputs = [ pkgs.gnugrep ];
}
