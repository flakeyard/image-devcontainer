{ config, pkgs, ... }:
{
  description = "Run the smoke tests of the image with docker";
  runtimeInputs = with pkgs; [
    binutils
    curl
    devcontainer
    findutils
    gawk
    gnugrep
    gnused
  ];
  environment = {
    EXPECTED = "${config.packages.image.expected}";
    EDITOR_SERVER = "${import ./editor-server.nix { inherit pkgs; }}";
  };
}
