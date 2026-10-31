# The apps that CI runs (FY-0009), one per body in the directories here: the
# body check/size.nix is the app check-size, which runs scripts/check/size.sh
# with the Nix of the runner. A directory with default.nix, such as smoke/, is
# one app, and its other files are parts of its body. A body is a function of
# config, lib and pkgs that returns the settings of its app for mkApp. The
# files here are modules; flake.nix imports no body.
{ lib, ... }:
let
  # bodiesIn PATH: the bodies under the directory PATH of the apps by their
  # path, such as { "check/size" = ./check/size.nix; } for "check".
  bodiesIn =
    path:
    let
      dir = ./. + "/${path}";
      entries = builtins.readDir dir;
      bodiesOf =
        name: type:
        if type == "directory" then
          bodiesIn "${path}/${name}"
        else if lib.hasSuffix ".nix" name then
          { "${path}/${lib.removeSuffix ".nix" name}" = dir + "/${name}"; }
        else
          { };
    in
    if entries ? "default.nix" then
      { ${path} = dir + "/default.nix"; }
    else
      lib.concatMapAttrs bodiesOf entries;

  # groupBodies NAME TYPE: the bodies under the directory NAME here; the files
  # here are not bodies.
  groupBodies = name: type: if type == "directory" then bodiesIn name else { };

  bodies = lib.concatMapAttrs groupBodies (builtins.readDir ./.);

  # appName PATH: the name of the app at PATH, such as check-size.
  appName = lib.replaceStrings [ "/" ] [ "-" ];
in
{
  perSystem =
    {
      config,
      mkApp,
      pkgs,
      ...
    }:
    let
      # app PATH BODY: the app at PATH with its name and script.
      app =
        path: body:
        let
          name = appName path;
          script = ../../scripts + "/${path}.sh";
          settings = import body { inherit config lib pkgs; };
        in
        lib.nameValuePair name (mkApp { inherit name script; } settings);
    in
    {
      apps = lib.mapAttrs' app bodies;
    };
}
