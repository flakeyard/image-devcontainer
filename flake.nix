{
  description = "Dev container image built with Nix: multi-user Nix, direnv and nix-direnv.";

  inputs = {
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?ref=nixos-26.05&rev=08d3a97586f6b6343b3b5e799980773629432610&shallow=1";
    flake-parts = {
      url = "git+https://github.com/hercules-ci/flake-parts?ref=main&rev=024633cd702b10285db5cb19b40ad48d2399ba60&shallow=1";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    import-tree.url = "git+https://github.com/vic/import-tree?ref=main&rev=eb1b52eaecc57f7c136d07ae8a93e724dfecac46&shallow=1";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      # Every file under nix/ is a flake-parts module, except the bodies of
      # apps in the directories of nix/apps/, which nix/apps/default.nix loads.
      imports = [ (inputs.import-tree.matchNot "/apps/[^/]+/.*" ./nix) ];
    };
}
