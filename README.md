# nix-pkgset

`nix-pkgset` is a lightweight library that helps package nix derivations into cross-compilation aware package sets by [splicing](https://nixos.org/manual/nixpkgs/stable/#ssec-cross-dependency-implementation) packages in the same fashion as [nixpkgs](https://github.com/NixOS/nixpkgs).

## Features

- Create spliced package sets (cross-compilation aware packages).
- Access non-spliced package sets through `pkgs<build><target>`.
- Merge package sets together (including spliced packages and non-spliced package sets).
- Avoid re-instantiating nixpkgs (see: [1000 instances of nixpkgs](https://zimbatm.com/notes/1000-instances-of-nixpkgs)).

## Planned features

- Standarize cross-compilation package sets by automatically generating `pkgsCross`.
- Avoid re-splicing when merging package sets

## Examples

### Creating package sets

```nix
let
  # Create a new package set that inherits the scope from `pkgs`.
  pkgset = nix-pkgset.lib.makePackageSet pkgs (self: {
    # We can reference spliced packages from `pkgs`.
    foo = self.callPackage ({ runCommand, hello, pkgsBuildBuild }:
      runCommand "foo" { nativeBuildInputs = [ hello ]; } ''
        # `nativeBuildInputs` packages are spliced to run on the build platform.
        hello

        # Packages can be referenced by `pkgs<build><host>`.
        ${pkgsBuildBuild.hello}/bin/hello

        # Packages are spliced to run on the host platform.
        mkdir -p $out/bin
        ln -s ${hello}/bin/hello $out/bin/foo
      ''
    ) { };

    # We can also reference spliced packages from `self`.
    bar = self.callPackage ({ runCommand, hello, foo, pkgsBuildBuild }:
      runCommand "bar" { nativeBuildInputs = [ hello foo ]; } ''
        # `nativeBuildInputs` packages are spliced to run on the build platform.
        hello
        foo

        # Packages can be referenced by `pkgs<build><host>`.
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
  hello = pkgset.hello; # Error: `hello` is not in the package set.

  # We can reference packages from the package set `pkgs<build><host>`.
  buildbuild-foo = pkgset.pkgsBuildBuild.foo;
  buildbuild-bar = pkgset.pkgsBuildBuild.bar;
  buildbuild-hello = pkgset.pkgsBuildBuild.hello; # Error: `hello` is not in the package set.

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
  hello = mergedPkgset.hello; # Error: `hello` is not in the package set.

  # We can reference packages from the package set `pkgs<build><host>`.
  buildbuild-foo = mergedPkgset.pkgsBuildBuild.foo;
  buildbuild-bar = mergedPkgset.pkgsBuildBuild.bar;
  buildbuild-hello = mergedPkgset.pkgsBuildBuild.hello; # Error: `hello` is not in the package set.

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
  pkgset = nix-pkgset.lib.makePackageSet pkgs (self: {
    foo = self.callPackage ({ hello }: hello) { };
  });

  # Merge `pkgs` (from nixpkgs) with `pkgset`.
  mergedPkgset = nix-pkgset.lib.mergePackageSets [ pkgs pkgset ];
in
{
  # We can reference packages from the package set.
  foo = mergedPkgset.foo;
  hello = mergedPkgset.hello;

  # We can reference packages from the package set `pkgs<build><host>`.
  buildbuild-foo = mergedPkgset.pkgsBuildBuild.foo;
  buildbuild-hello = mergedPkgset.pkgsBuildBuild.hello;
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
      forAllCrossPlatforms = lib.genAttrs (lib.attrNames lib.systems.examples);

      makePackageSetFor = pkgs: nix-pkgset.lib.makePackageSet pkgs (self: {
        foo = self.callPackage ({ hello }: hello) { };
      });
    in
    {
      # legacyPackages.<system>.foo
      # legacyPackages.<system>.pkgsBuildBuild.foo
      # legacyPackages.<system>.pkgsCross.aarch64-multiplatform.foo
      # legacyPackages.<system>.pkgsCross.aarch64-multiplatform.pkgsBuildBuild.foo
      legacyPackages = forAllSystems (system:
        makePackageSetFor nixpkgs.legacyPackages.${system} // {
          # TODO: Right now we have to define `pkgsCross` manually.
          pkgsCross = forAllCrossPlatforms (crossPlatform:
            makePackageSetFor nixpkgs.legacyPackages.${system}.pkgsCross.${crossPlatform}
          );
        }
      );

      # packages.<system>.foo
      packages = forAllSystems (system:
        lib.filterAttrs (_: lib.isDerivation) self.legacyPackages.${system}
      );
    };
}
```

### Importing pkgsets from flakes (WIP)

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
            bar = self.callPackage ({ hello }: hello) { };
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
          # TODO: This should be `pkgs.pkgsCross.<crossPlatform>`, but it isn't supported yet.
          spliced = pkgs.callPackage ({ mkShell, hello, foo, bar }:
            mkShell {
              nativeBuildInputs = [ hello foo ];
              buildInput = [ bar ];
            }
          ) { };
        }
      );
    };
}
```
