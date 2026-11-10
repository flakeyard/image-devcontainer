# The shell library at the commit that the job image of test.yaml pins, for
# the unit tests: the commit is read from test.yaml, so the repository pins it
# once (ADR-0001 of action-shell-lib).
{
  perSystem =
    _:
    let
      pin = builtins.match ".*uses: flakeyard/action-shell-lib@([0-9a-f]{40}) .*" (
        builtins.readFile ../.github/workflows/test.yaml
      );
    in
    {
      _module.args.shellLib =
        if pin == null then
          throw "test.yaml pins no commit of flakeyard/action-shell-lib"
        else
          builtins.fetchGit {
            url = "https://github.com/flakeyard/action-shell-lib";
            rev = builtins.head pin;
            shallow = true;
          };
    };
}
