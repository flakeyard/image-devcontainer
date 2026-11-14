# devShells.flakeyard-project: the tools that tests/run.sh needs and no atom
# provides yet; atom-workspace joins them into devShells.default.
{
  perSystem =
    { pkgs, ... }:
    {
      devShells.flakeyard-project = pkgs.mkShellNoCC {
        packages = with pkgs; [
          jq
          yq-go
        ];
      };
    };
}
