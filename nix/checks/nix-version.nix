# One Nix version: nix-direnv uses the image's Nix.
{
  perSystem =
    { config, pkgs, ... }:
    let
      inherit (config.image) parts;
    in
    {
      checks.nix-version = pkgs.runCommand "nix-version" { } ''
        grep -q "${parts.nix}" "${parts.nix-direnv}/share/nix-direnv/direnvrc"
        touch $out
      '';
    };
}
