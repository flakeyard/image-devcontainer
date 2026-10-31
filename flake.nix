{
  description = "Dev container image built with Nix: multi-user Nix, direnv and nix-direnv.";

  inputs.nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?ref=nixos-26.05&rev=08d3a97586f6b6343b3b5e799980773629432610&shallow=1";

  outputs =
    { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      # Unfree packages fail evaluation: the image must be redistributable
      # (FY-0013, FY-0027). Instantiated once per system for every output.
      perSystem = lib.genAttrs systems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = false;
          };
          parts = import ./nix/parts.nix { inherit pkgs; };
        in
        {
          inherit pkgs parts;
          image = import ./nix/image.nix { inherit pkgs parts; };
        }
      );
      forAll = f: lib.mapAttrs (_: f) perSystem;
    in
    {
      formatter = forAll (args: args.pkgs.nixfmt);

      packages = forAll (args: {
        # The image as a script that streams a docker archive to stdout.
        inherit (args) image;
      });

      apps = forAll (import ./nix/apps.nix);

      checks = forAll (import ./nix/checks.nix);
    };
}
