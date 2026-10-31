# The Nix of the image: the minor version of action-setup-nix (FY-0009).
{
  perSystem =
    { pkgs, ... }:
    {
      image.parts.nix = pkgs.nixVersions.nix_2_35;
    };
}
