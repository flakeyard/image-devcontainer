{
  description = "A project for the smoke tests: a shell without inputs, for `use flake`.";

  # Must be ignored: dev is not a trusted user and accept-flake-config is off.
  nixConfig.extra-substituters = [ "https://untrusted.invalid" ];

  outputs =
    { self }:
    let
      shell =
        system:
        derivation {
          name = "fixture-shell";
          inherit system;
          # nix develop and nix-direnv need a bash builder.
          builder = "/bin/bash";
          args = [
            "-c"
            "echo >$out"
          ];
          FIXTURE_VARIABLE = "from the project shell";
        };
    in
    {
      devShells.x86_64-linux.default = shell "x86_64-linux";
      devShells.aarch64-linux.default = shell "aarch64-linux";
    };
}
