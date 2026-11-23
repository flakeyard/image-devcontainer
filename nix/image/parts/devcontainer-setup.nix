# devcontainer-setup (ADR-0002), the postCreateCommand of projects: sets up
# the workspace and fails on a broken shell, a missing hook or a worktree
# outside the workspace. writeShellApplication runs shellcheck on it. Its
# tools are those of the image, so that it adds no store paths but its own.
{
  perSystem =
    { pkgs, root, ... }:
    {
      image.parts.devcontainer-setup = pkgs.writeShellApplication {
        name = "devcontainer-setup";
        runtimeInputs = with pkgs; [
          coreutils
          direnv
          gitMinimal
          gnugrep
          util-linuxMinimal
        ];
        text = builtins.readFile (root + "/setup/devcontainer-setup.sh");
      };
    };
}
