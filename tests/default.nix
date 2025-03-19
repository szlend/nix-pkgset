{ inputs, system }:

let
  pkgs = inputs.nixpkgs.legacyPackages.${system};
  nix-pkgset = inputs.self;

  rust-overlay = import (
    builtins.fetchTarball {
      url = "https://github.com/oxalica/rust-overlay/archive/af76221b285a999ab7d9d77fce8ba1db028f9801.tar.gz";
      sha256 = "03zc2w66zz8dkrxpy39lrh3gqand1ypmnhcakmhibs9ndyi4v3x0";
    }
  );

  # Pick an arbitrary foreign nixpkgs package set.
  foreignPlatform = if pkgs.stdenv.isAarch64 then "gnu64" else "aarch64-multiplatform";
  pkgsForeign = pkgs.pkgsCross.${foreignPlatform};

  # Create our package set.
  makePackageSetFor =
    pkgs:
    nix-pkgset.lib.makePackageSet "pkgset" pkgs.newScope (self: {
      my-foo = self.callPackage ./my-foo.nix { };
      my-bar = self.callPackage ./my-bar.nix { };
      rust-bin = self.callPackage (
        { lib, pkgs }: (lib.fix (lib.extends rust-overlay (_self: pkgs))).rust-bin
      ) { };
    });

  pkgset = makePackageSetFor pkgs;
  pkgsetForeign = makePackageSetFor pkgsForeign;

  # Make mock flake
  mkFlake =
    path: inputsf:
    let
      inputs = inputsf // {
        self = fSelf;
      };
      fSelf = {
        inherit inputs;
        outPath = ./.;
      } // (import path).outputs inputs;
    in
    fSelf;

  flake = mkFlake ./flake.nix {
    nixpkgs = inputs.nixpkgs;
    nix-pkgset = inputs.self;
  };
in
{
  # makePackageSet
  my-bar = pkgset.my-bar;
  my-bar-foreign = pkgsetForeign.my-bar;

  buildbuild-my-bar = pkgset.pkgsetBuildBuild.my-bar;
  buildbuild-my-bar-foreign = pkgsetForeign.pkgsetBuildBuild.my-bar;

  buildhost-my-bar = pkgset.pkgsetBuildHost.my-bar;
  buildhost-my-bar-foreign = pkgsetForeign.pkgsetBuildHost.my-bar;

  my-bar-call-package = pkgset.callPackage (
    { my-bar }:
    assert (!my-bar ? __spliced);
    my-bar
  ) { };

  my-bar-call-package-foreign = pkgsetForeign.callPackage (
    { my-bar }:
    assert my-bar ? __spliced;
    my-bar
  ) { };

  buildhost-my-bar-call-package = pkgset.pkgsetBuildHost.callPackage (
    { my-bar }:
    assert (!my-bar ? __spliced);
    my-bar
  ) { };

  buildhost-my-bar-call-package-foreign = pkgsetForeign.pkgsetBuildHost.callPackage (
    { my-bar }:
    assert my-bar ? __spliced;
    my-bar
  ) { };

  flake-legacy-packages-my-foo = flake.legacyPackages.${system}.my-foo;
  flake-legacy-packages-my-bar = flake.legacyPackages.${system}.my-bar;

  flake-packages-my-foo = flake.packages.${system}.my-foo;
  flake-packages-my-bar = flake.packages.${system}.my-bar;

  rust-bin-stable = pkgset.rust-bin.stable.latest.minimal;

  rust-bin-stable-call-package-buildhost-foreign = pkgsetForeign.callPackage (
    { pkgsetBuildHost }:
    assert (!pkgsetBuildHost.rust-bin.stable.latest.minimal ? __spliced);
    pkgsetBuildHost.rust-bin.stable.latest.minimal
  ) { };

  rust-bin-stable-call-package-buildhost-call-package-foreign = pkgsetForeign.callPackage (
    { pkgsetBuildHost }:
    pkgsetBuildHost.callPackage (
      { rust-bin }:
      assert rust-bin.stable.latest.minimal ? __spliced;
      rust-bin.stable.latest.minimal
    ) { }
  ) { };

  buildhost-rust-bin-stable-foreign = pkgsetForeign.pkgsetBuildHost.rust-bin.stable.latest.minimal;

  buildhost-rust-bin-stable-call-package-foreign = pkgsetForeign.pkgsetBuildHost.callPackage (
    { rust-bin }:
    assert rust-bin.stable.latest.minimal ? __spliced;
    rust-bin.stable.latest.minimal
  ) { };

  rust-stable = pkgset.callPackage (
    {
      runCommand,
      rust,
      rust-bin,
    }:
    runCommand "rustc-version" { nativeBuildInputs = [ rust-bin.stable.latest.minimal ]; } ''
      rustc --version
      rust_dir=$(dirname $(dirname $(type -P rustc)))
      (set -x; test -d $rust_dir/lib/rustlib/${rust.lib.envVars.rustTargetPlatform})
      ln -s $rust_dir $out
    ''
  ) { };

  rust-stable-foreign = pkgsetForeign.callPackage (
    {
      runCommand,
      rust,
      rust-bin,
    }:
    runCommand "rustc-version" { nativeBuildInputs = [ rust-bin.stable.latest.minimal ]; } ''
      rustc --version
      rust_dir=$(dirname $(dirname $(type -P rustc)))
      (set -x; test -d $rust_dir/lib/rustlib/${rust.lib.envVars.rustTargetPlatform})
      ln -s $rust_dir $out
    ''
  ) { };
}
