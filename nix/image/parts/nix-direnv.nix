# nix-direnv falls back to its own nix; it must be the image's.
{
  perSystem =
    { config, pkgs, ... }:
    {
      image.parts.nix-direnv = pkgs.nix-direnv.override { inherit (config.image.parts) nix; };
    };
}
