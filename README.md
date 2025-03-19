# nix-pkgset

`nix-pkgset` is a lightweight library that helps package nix derivations into cross-compilation aware package sets by [splicing](https://nixos.org/manual/nixpkgs/stable/#ssec-cross-dependency-implementation) packages in the same fashion as [nixpkgs](https://github.com/NixOS/nixpkgs).

## Features

- Create package sets with splicing support (cross-compilation aware packages).
- Access non-spliced packages through `<pkgset-name><host><target>` (e.g. `pkgset.myPkgsBuildHost`).
- Access spliced packages without `callPackage` through `<pkgset-name>` (e.g. `pkgset.myPkgs`).

## Usage

```
nix-pkgset.lib.makePackageSet <name> <newScope> <scopeFn>
```

- **name**: The name of the package set. This will be used to define splices like `<name>BuildHost`, `<name>BuildTarget`.
- **newScope**: The scope to use as the base of your package set (usually `pkgs.newScope`). These packages will be available in `pkgset.callPackage` scope alongside your custom packages defined in `scopeFn`.
- **scopeFn**: The function used to define your package set. Packages defined in this function will be publically available (e.g. `pkgset.foo`). See nixpkgs [makeScope](https://nixos.org/manual/nixpkgs/unstable/#function-library-lib.customisation.makeScope) for more details.

## Example

```nix
let
  # Create a new package set that inherits the scope from `pkgs`.
  myPkgs = nix-pkgset.lib.makePackageSet "myPkgs" pkgs.newScope (self: {
    foo = self.callPackage ./foo.nix { };
    bar = self.callPackage ./bar.nix { };
  });
in
{
  # We can reference packages from the package set.
  foo = myPkgs.foo;
  bar = myPkgs.bar;

  # We can't reference packages that are not in the package set.
  # Package `hello` is only available in `callPackage` scope.
  hello = myPkgs.hello; # Error

  # We can reference package splices from `<pkgset><host><target>`.
  buildbuild-foo = myPkgs.myPkgsBuildBuild.foo;
  buildbuild-bar = myPkgs.myPkgsBuildBuild.bar;

  # We can't reference packages that are not in the package set.
  # Package `hello` is only available in `callPackage` scope.
  buildbuild-hello = myPkgs.myPkgsBuildBuild.hello; # Error

  # We can access pre-spliced packages.
  foo-spliced = myPkgs.myPkgs.foo; # `foo-spliced.__spliced` is set
  bar-spliced = myPkgs.myPkgs.bar;

  # We can create a derivation based on the package set's scope.
  baz = myPkgs.callPackage ({ stdenv, hello, bar, foo }:
    stdenv.mkDerivation {
      name = "baz";
      # `nativeBuildInputs` are spliced to run on the build platform.
      nativeBuildInputs = [ hello bar ];
      # `buildInputs` are spliced to run on the host platform.
      buildInputs = [ foo ];
      # ...
    }
  ) { };
}
```

## Flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-pkgset.url = "github:github.com/szlend/nix-pkgset";
    nix-pkgset.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-pkgset,
      ...
    }:

    let
      lib = nixpkgs.lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;
    in
    {
      legacyPackages = forAllSystems (
        system:

        nix-pkgset.lib.makePackageSet "foo" nixpkgs.legacyPackages.${system}.newScope (self: {
          # ...
        })
      );

      packages = forAllSystems (
        system:

        lib.filterAttrs (_: lib.isDerivation) self.legacyPackages.${system}
      );
    };
}
```
