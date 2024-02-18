{ pkgs, nix-pkgset }:

let
  rustOverlay = import (builtins.fetchTarball {
    url = "https://github.com/oxalica/rust-overlay/archive/d500e370b26f9b14303cb39bf1509df0a920c8b0.tar.gz";
    sha256 = "056qhc1bv5s4rf8nvmgxacqqfdjb8rky6g60cgwivqagvdgsaayd";
  });

  # Pick an arbitrary foreign nixpkgs package set.
  pkgsForeign = if pkgs.stdenv.isAarch64 then pkgs.pkgsCross.gnu64 else pkgs.pkgsCross.aarch64-multiplatform;

  # Create our package set.
  makePackageSetFor = pkgs: nix-pkgset.lib.makePackageSet pkgs (self: {
    my-foo = self.callPackage ./my-foo.nix { };
    my-bar = self.callPackage ./my-bar.nix { };
  });

  pkgset = makePackageSetFor pkgs;
  pkgsetForegin = makePackageSetFor pkgsForeign;

  mergedPkgset = nix-pkgset.lib.mergePackageSets [ pkgs pkgset ];
  mergedPkgsetForeign = nix-pkgset.lib.mergePackageSets [ pkgsForeign pkgsetForegin ];

  makeRustOverlayPkgsetFor = pkgs: nix-pkgset.lib.packageSetFromOverlay pkgs rustOverlay;
  rustOverlayPkgset = makeRustOverlayPkgsetFor pkgs;
  rustOverlayPkgsetForeign = makeRustOverlayPkgsetFor pkgsForeign;
in
{
  # makePackageSet
  my-bar = pkgset.my-bar;
  my-bar-foreign = pkgsetForegin.my-bar;

  buildbuild-my-bar = pkgset.pkgsBuildBuild.my-bar;
  buildbuild-my-bar-foreign = pkgsetForegin.pkgsBuildBuild.my-bar;

  buildhost-my-bar = pkgset.pkgsBuildHost.my-bar;
  buildhost-my-bar-foreign = pkgsetForegin.pkgsBuildHost.my-bar;

  # mergePackageSets
  merged-hello = mergedPkgset.hello;
  merged-hello-foreign = mergedPkgsetForeign.hello;
  merged-my-bar = mergedPkgset.my-bar;
  merged-my-bar-foreign = mergedPkgsetForeign.my-bar;

  merged-buildbuild-hello = mergedPkgset.pkgsBuildBuild.hello;
  merged-buildbuild-hello-foreign = mergedPkgsetForeign.pkgsBuildBuild.hello;
  merged-buildbuild-my-bar = mergedPkgset.pkgsBuildBuild.my-bar;
  merged-buildbuild-my-bar-foreign = mergedPkgsetForeign.pkgsBuildBuild.my-bar;

  merged-buildhost-hello = mergedPkgset.pkgsBuildHost.hello;
  merged-buildhost-hello-foreign = mergedPkgsetForeign.pkgsBuildHost.hello;
  merged-buildhost-my-bar = mergedPkgset.pkgsBuildHost.my-bar;
  merged-buildhost-my-bar-foreign = mergedPkgsetForeign.pkgsBuildHost.my-bar;

  # packageSetFromOverlay
  rust-stable = rustOverlayPkgset.callPackage
    ({ runCommand, rust, rust-bin }:
      runCommand "rustc-version" { nativeBuildInputs = [ rust-bin.stable.latest.minimal ]; } ''
        rustc --version
        rust_dir=$(dirname $(dirname $(type -P rustc)))
        (set -x; test -d $rust_dir/lib/rustlib/${rust.lib.envVars.rustTargetPlatform})
        ln -s $rust_dir $out
      ''
    )
    { };

  rust-stable-foreign = rustOverlayPkgsetForeign.callPackage
    ({ runCommand, rust, rust-bin }:
      runCommand "rustc-version" { nativeBuildInputs = [ rust-bin.stable.latest.minimal ]; } ''
        rustc --version
        rust_dir=$(dirname $(dirname $(type -P rustc)))
        (set -x; test -d $rust_dir/lib/rustlib/${rust.lib.envVars.rustTargetPlatform})
        ln -s $rust_dir $out
      ''
    )
    { };
}
