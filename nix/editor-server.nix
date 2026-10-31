# VS Code Server, pinned, for the smoke tests only: the binaries the image
# serves through nix-ld. Unpacked without patching, as an editor installs it.
# Never part of the image; its license is accepted only by the tests.
{ pkgs }:
let
  commit = "2c33b50b16c472efe58357d1d2a8a5414bc23fbf"; # 1.144.0
  platforms = {
    x86_64-linux = {
      name = "linux-x64";
      sha256 = "65a713d95bb598310ad86db4daea28f9c3f9687b59ee9e57b3e7060a810bf916";
    };
    aarch64-linux = {
      name = "linux-arm64";
      sha256 = "21c57e906a30441a843247861ac473a0e4eeed3599529ced0623e6afa93a7fd5";
    };
  };
  platform = platforms.${pkgs.stdenv.hostPlatform.system};
  tarball = pkgs.fetchurl {
    url = "https://vscode.download.prss.microsoft.com/dbazure/download/stable/${commit}/vscode-server-${platform.name}.tar.gz";
    inherit (platform) sha256;
  };
in
pkgs.runCommand "vscode-server-${commit}" { } ''
  mkdir $out
  tar -xzf ${tarball} -C $out --strip-components=1
''
