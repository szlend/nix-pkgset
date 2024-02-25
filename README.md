# nix-pkgset

`nix-pkgset` is a lightweight library that helps package nix derivations into cross-compilation aware package sets by [splicing](https://nixos.org/manual/nixpkgs/stable/#ssec-cross-dependency-implementation) packages in the same fashion as [nixpkgs](https://github.com/NixOS/nixpkgs).

**WARNING:** The library is still in proof of concept stage and the API is subject to change.

## Features

- Create package sets with splicing support (cross-compilation aware packages).
- Access non-spliced packages through `pkgs<host><target>`.
- Access extra package set variants like `pkgsCross.<crossSystem>` and `pkgsLLVM`.
- Avoid re-instantiating nixpkgs (see: [1000 instances of nixpkgs](https://zimbatm.com/notes/1000-instances-of-nixpkgs)).
- Merge package sets together while keeping all of the above.

## Planned features

- Optimize unnecessary re-splicing of packages.
- Optimize unnecessary re-evaluation on equivalent `pkgs<host><target>` sets.

## Examples

### Creating package sets

```nix
let
  # Create a new package set that inherits the scope from `pkgs`.
  pkgset = nix-pkgset.lib.makePackageSet pkgs (self: {
    # Create package `foo` which depends on `hello` at build time and run time.
    foo = self.callPackage ({ runCommand, hello, pkgsBuildBuild }:
      runCommand "foo" { nativeBuildInputs = [ hello ]; } ''
        # `nativeBuildInputs` packages are spliced to run on the build platform.
        hello

        # Packages can be referenced by `pkgs<host><target>`.
        ${pkgsBuildBuild.hello}/bin/hello

        # Packages are spliced to run on the host platform.
        mkdir -p $out/bin
        ln -s ${hello}/bin/hello $out/bin/foo
      ''
    ) { };

    # Create package `bar` which depends on `hello` and `foo` at build time and run time.
    bar = self.callPackage ({ runCommand, hello, foo, pkgsBuildBuild }:
      runCommand "bar" { nativeBuildInputs = [ hello foo ]; } ''
        # `nativeBuildInputs` packages are spliced to run on the build platform.
        hello
        foo

        # Packages can be referenced by `pkgs<host><target>`.
        ${pkgsBuildBuild.hello}/bin/hello
        ${pkgsBuildBuild.foo}/bin/foo

        # Packages are spliced to run on the host platform.
        mkdir -p $out/bin
        ln -s ${hello}/bin/hello $out/bin/hello
        ln -s ${foo}/bin/foo $out/bin/foo
      ''
    ) { };
  });
in
{
  # We can reference packages from the package set.
  foo = pkgset.foo;
  bar = pkgset.bar;

  # We can't reference packages that are not in the package set.
  # Package `hello` is only available in `callPackage` scope.
  hello = pkgset.hello; # Error

  # We can reference packages from the package set `pkgs<host><target>`.
  buildbuild-foo = pkgset.pkgsBuildBuild.foo;
  buildbuild-bar = pkgset.pkgsBuildBuild.bar;

  # We can't reference packages that are not in the package set.
  # Package `hello` is only available in `callPackage` scope.
  buildbuild-hello = pkgset.pkgsBuildBuild.hello; # Error

  # We can create a derivation based on the package set's scope.
  baz = pkgset.callPackage ({ mkDerivation, hello, bar, foo }:
    mkDerivation {
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

### Merging package sets

```nix
let
  firstPkgset = nix-pkgset.lib.makePackageSet pkgs (self: {
    foo = self.callPackage ({ hello }: hello) { };
  });

  secondPkgset = nix-pkgset.lib.makePackageSet pkgs (self: {
    bar = self.callPackage ({ hello }: hello) { };
  });

  mergedPkgset = nix-pkgset.lib.mergePackageSets [ firstPkgset secondPkgset ];
in
{
  # We can reference packages from the package set.
  foo = mergedPkgset.foo;
  bar = mergedPkgset.bar;
  # We can't reference packages that are not in the package set.
  # Package `hello` is only available in `callPackage` scope.
  hello = mergedPkgset.hello; # Error

  # We can reference packages from the package set `pkgs<host><target>`.
  buildbuild-foo = mergedPkgset.pkgsBuildBuild.foo;
  buildbuild-bar = mergedPkgset.pkgsBuildBuild.bar;

  # We can't reference packages that are not in the package set.
  # Package `hello` is only available in `callPackage` scope.
  buildbuild-hello = mergedPkgset.pkgsBuildBuild.hello; # Error

  # We can create a derivation based on the package set's scope.
  baz = mergedPkgset.callPackage ({ mkDerivation, hello, bar, foo }:
    mkDerivation {
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

### Extending `nixpkgs`

```nix
let
  myPkgset = nix-pkgset.lib.makePackageSet pkgs (self: {
    foo = self.callPackage ({ hello }: hello) { };
  });

  # Merge `pkgs` (from nixpkgs) with `myPkgset`.
  mergedPkgset = nix-pkgset.lib.mergePackageSets [ pkgs myPkgset ];
in
{
  # We can reference packages from the package set.
  foo = mergedPkgset.foo; # From `myPkgset`
  hello = mergedPkgset.hello; # From `pkgs`

  # We can reference packages from the package set `pkgs<host><target>`.
  buildbuild-foo = mergedPkgset.pkgsBuildBuild.foo; # From `myPkgset`
  buildbuild-hello = mergedPkgset.pkgsBuildBuild.hello; # From `pkgs`
}
```

### Working with overlays

```nix
let
  # Create a package set from an overlay instead on instantiating a new nixpkgs instance.
  rustOverlay = nix-pkgset.lib.packageSetFromOverlay pkgs (import rust-overlay);
in
{
  rust-stable = rustOverlay.rust-bin.stable.latest.minimal;
}
```

### Exporting pkgsets from flakes

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-pkgset.url = "github:szlend/nix-pkgset";
    nix-pkgset.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nix-pkgset, ... }:
    let
      lib = nixpkgs.lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;

      makePackageSetFor = pkgs: nix-pkgset.lib.makePackageSet pkgs (self: {
        foo = self.callPackage ({ hello }: hello) { }; # Just re-export `hello` as `foo`
      });
    in
    {
      # legacyPackages.<system>.foo
      # legacyPackages.<system>.pkgsBuildBuild.foo
      # legacyPackages.<system>.pkgsCross.aarch64-multiplatform.foo
      # legacyPackages.<system>.pkgsCross.aarch64-multiplatform.pkgsBuildBuild.foo
      legacyPackages = forAllSystems (system:
        makePackageSetFor nixpkgs.legacyPackages.${system}
      );

      # packages.<system>.foo
      packages = forAllSystems (system:
        lib.filterAttrs (_: lib.isDerivation) self.legacyPackages.${system}
      );
    };
}
```

### Importing pkgsets from flakes

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-pkgset.url = "github:szlend/nix-pkgset";
    nix-pkgset.inputs.nixpkgs.follows = "nixpkgs";

    foo-pkgset.url = "/my/foo-pkgset";
    foo-pkgset.inputs.nix-pkgset.follows = "nix-pkgset";
    foo-pkgset.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nix-pkgset, foo-pkgset, ... }:
    let
      lib = nixpkgs.lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;

      makePackageSetForSystem = system:
        let
          # Contains the entire nixpkgs package set.
          pkgs = nixpkgs.legacyPackages.${system};
          # Contains `foo` from `foo-pkgset`.
          fooPkgset = foo-pkgset.legacyPackages.${system};
          # Contains `bar`
          barPkgset = nix-pkgset.lib.makePackageSet pkgs (self: {
            bar = self.callPackage ({ hello }: hello) { }; # Just re-export `hello` as `bar`
          });
        # Merge all package sets
        in nix-pkgset.lib.mergePackageSets [ pkgs fooPkgset barPkgset ];
    in
    {
      devShells = forAllSystems (system:
        let
          # Create a merged package set for this system.
          pkgs = makePackageSetForSystem system;
        in
        {
          # A non-spliced devShell (doesn't care about cross-compilation).
          default = pkgs.mkShell {
            packages = [ pkgs.hello pkgs.foo pkgs.bar ];
          };

          # A spliced devShell (packages are set up for cross-compilation).
          spliced = pkgs.pkgsCross.aarch64-multiplatform.callPackage ({ mkShell, hello, foo, bar }:
            mkShell {
              nativeBuildInputs = [ hello foo ];
              buildInputs = [ bar ];
            }
          ) { };
        }
      );
    };
}
```
