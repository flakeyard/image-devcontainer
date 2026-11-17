# The shell library at the commit that the job image of test.yaml pins, for
# the unit tests and the app publish-verify: the commit is read from
# test.yaml, which names it like every other use of the library (ADR-0001 of
# lib-actions).
{
  perSystem =
    { root, ... }:
    let
      pin = builtins.match ".*uses: flakeyard/lib-actions@([0-9a-f]{40}) .*" (
        builtins.readFile (root + "/.github/workflows/test.yaml")
      );
    in
    {
      _module.args.shellLib =
        if pin == null then
          throw "test.yaml pins no commit of flakeyard/lib-actions"
        else
          builtins.fetchGit {
            url = "https://github.com/flakeyard/lib-actions";
            rev = builtins.head pin;
            shallow = true;
          };
    };
}
