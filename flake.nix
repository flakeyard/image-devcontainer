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
      # (FY-0013, FY-0027).
      forAll =
        f:
        lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              config.allowUnfree = false;
            }
          )
        );
    in
    {
      formatter = forAll (pkgs: pkgs.nixfmt);

      packages = forAll (pkgs: {
        # The image as a script that streams a docker archive to stdout.
        image = import ./nix/image.nix {
          inherit pkgs;
          parts = import ./nix/parts.nix { inherit pkgs; };
        };
      });

      apps = forAll (pkgs: import ./nix/apps.nix { inherit pkgs; });

      checks = forAll (pkgs: import ./nix/checks.nix { inherit pkgs; });
    };
}
