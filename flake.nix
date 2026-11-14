{
  description = "Dev container image built with Nix: multi-user Nix, direnv and nix-direnv.";

  inputs = {
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?ref=nixos-26.05&rev=c56a87d8e41ce69bd2af57eb35dcc117a9dfca33&shallow=1";
    flake-parts = {
      url = "git+https://github.com/hercules-ci/flake-parts?ref=main&rev=ea2630b7470978622c7689a1ff75d2b389175399&shallow=1";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    git-hooks = {
      url = "git+https://github.com/cachix/git-hooks.nix?ref=master&rev=204b6977e00caac19e2313015a598543ca7be150&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    atom-workflows = {
      url = "git+https://github.com/flakeyard/atom-workflows?ref=v0&rev=82957679afb098f2c36fbcc1ccdf5d52f3286ba4&shallow=1";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-workspace.url = "git+https://github.com/flakeyard/atom-workspace?ref=v0&rev=53d4d101ec71025dbb19da3d423455e72e10198a&shallow=1";
    import-tree.url = "git+https://github.com/vic/import-tree?ref=main&rev=eb1b52eaecc57f7c136d07ae8a93e724dfecac46&shallow=1";
  };

  outputs =
    inputs:
    let
      # The root of the repository (FY-0039): the other Nix files reach its
      # files only as root + "/<path from the root>".
      root = ./.;
    in
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      imports = [
        inputs.atom-workflows.flakeModules.default
        inputs.atom-workspace.flakeModules.default
        # Every file under nix/ is a flake-parts module, except the bodies of
        # apps in the directories of nix/apps/, which nix/apps/default.nix loads.
        (inputs.import-tree.matchNot "/apps/[^/]+/.*" ./nix)
      ];
      _module.args.root = root;
      perSystem._module.args.root = root;
    };
}
