{
  description = "Dev container image built with Nix: multi-user Nix, direnv and nix-direnv.";

  inputs = {
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?ref=nixos-26.05&rev=0dc498bfe49baeb18b0f9891e800b53bb2603193&shallow=1";
    flake-parts = {
      url = "git+https://github.com/hercules-ci/flake-parts?ref=main&rev=ea2630b7470978622c7689a1ff75d2b389175399&shallow=1";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    git-hooks = {
      url = "git+https://github.com/cachix/git-hooks.nix?ref=master&rev=204b6977e00caac19e2313015a598543ca7be150&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "git+https://github.com/numtide/treefmt-nix?ref=main&rev=a0a97e31a897a3537eea5c49df4f8adaa83b3b37&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    atom-data-formats = {
      url = "git+https://github.com/flakeyard/atom-data-formats?ref=v0&rev=933cbb3ff234825dd19a55c91a1bb279ea2682cb&shallow=1";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-markdown = {
      url = "git+https://github.com/flakeyard/atom-markdown?ref=v0&rev=90a9dc7b59521c187fabd6662205b88e712d088d&shallow=1";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-nix = {
      url = "git+https://github.com/flakeyard/atom-nix?ref=v0&rev=c591b0716c9fe3f16074637e63ee9128e602ee6a&shallow=1";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-shell = {
      url = "git+https://github.com/flakeyard/atom-shell?ref=v0&rev=912d34e8313d5d300c49c6484466bbcb396aab46&shallow=1";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-text = {
      url = "git+https://github.com/flakeyard/atom-text?ref=v0&rev=68467987a5d8db04681d587ffaa2d9aa755a4f62&shallow=1";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-workflows = {
      url = "git+https://github.com/flakeyard/atom-workflows?ref=v0&rev=5eeed2dd0411ebdd186d37bc401712edc5069aa1&shallow=1";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-workspace.url = "git+https://github.com/flakeyard/atom-workspace?ref=v0&rev=19b05dd722aa405c6110364ca60438d94855d1fe&shallow=1";
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
        inputs.atom-data-formats.flakeModules.default
        inputs.atom-markdown.flakeModules.default
        inputs.atom-nix.flakeModules.default
        inputs.atom-shell.flakeModules.default
        inputs.atom-text.flakeModules.default
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
