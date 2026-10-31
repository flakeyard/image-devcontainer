# Support for foreign binaries, such as editor servers built for other
# distributions (FY-0005): nix-ld at the standard loader path, with the
# libraries those binaries need. Measured with readelf on VS Code Server: all
# its ELF files need glibc, libstdc++ and libgcc_s only. The smoke tests check
# that the set is still enough and nothing more.
{ pkgs }:
let
  inherit (pkgs) lib stdenv;
in
rec {
  libraries = [ stdenv.cc.cc.lib ];
  libraryPath = lib.makeLibraryPath libraries;

  # The loader path of this architecture, as nix-ld computes it.
  loader = "${stdenv.hostPlatform.libDir}/${baseNameOf stdenv.cc.bintools.dynamicLinker}";

  # Store paths used through links outside the store.
  paths = [
    pkgs.nix-ld
    pkgs.glibc
  ]
  ++ map lib.getLib libraries;

  # Commands for the image root: the loader and the libraries that installers
  # of editor servers look for at standard paths.
  links = ''
    mkdir -p ${dirOf loader} usr/lib
    ln -s ${pkgs.nix-ld}/libexec/nix-ld ${loader}
    ln -s ${lib.getLib stdenv.cc.cc.lib}/lib/libstdc++.so.6 usr/lib/libstdc++.so.6
    ln -s ${pkgs.glibc}/lib/libc.so.6 usr/lib/libc.so.6
  '';
}
