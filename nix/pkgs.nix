# The nixpkgs of every output, instantiated once per system. Unfree packages
# fail evaluation: the image must be redistributable (FY-0013, FY-0027).
{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = false;
      };
    };
}
