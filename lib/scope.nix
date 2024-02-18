{ lib }:

let
  mergeSplices = a: b: rec {
    pkgsBuildBuild = a.pkgsBuildBuild // b.pkgsBuildBuild;
    pkgsBuildHost = a.pkgsBuildHost // b.pkgsBuildHost;
    pkgsBuildTarget = a.pkgsBuildTarget // b.pkgsBuildTarget;
    pkgsHostHost = a.pkgsHostHost // b.pkgsHostHost;
    pkgsHostTarget = a.pkgsHostTarget // b.pkgsHostTarget;
    pkgsTargetTarget = a.pkgsTargetTarget // b.pkgsTargetTarget;

    buildPackages = pkgsBuildHost;
    pkgs = pkgsHostTarget;
    targetPackages = pkgsTargetTarget;
  };

  makeSplices = splices: self: f: {
    pkgsBuildBuild = makeScope splices.pkgsBuildBuild.newScope f;
    pkgsBuildHost = makeScope splices.pkgsBuildHost.newScope f;
    pkgsBuildTarget = makeScope splices.pkgsBuildTarget.newScope f;
    pkgsHostHost = makeScope splices.pkgsHostHost.newScope f;
    pkgsHostTarget = self;
    pkgsTargetTarget = makeScope splices.pkgsTargetTarget.newScope f;

    buildPackages = self.pkgsBuildHost;
    pkgs = self;
    targetPackages = self.pkgsTargetTarget;
  };

  newScopeSplices = newScope: newScope { }
    ({ pkgsBuildBuild
     , pkgsBuildHost
     , pkgsBuildTarget
     , pkgsHostHost
     , pkgsHostTarget
     , pkgsTargetTarget
     } @ splices: splices)
    { };

  # Adapted from https://github.com/NixOS/nixpkgs/blob/3378e4ec169425e7434d101f32680c068799a0f4/lib/customisation.nix
  # Changes:
  #  - Include own splices in `self`
  #  - Include merged splices in `newScope`
  makeScope = newScope: f:
    let
      baseSplices = newScopeSplices newScope;
      selfSplices = makeSplices baseSplices self f;

      self = f self // selfSplices // {
        newScope = scope: newScope (self // mergeSplices baseSplices selfSplices // scope);
        callPackage = self.newScope { };
        overrideScope = g: makeScope newScope (lib.extends g f);
        packages = f;

        # TODO: Not sure if this is a good idea, but it's convenient for avoiding infinite
        # recursion or accessing shadowed packages.
        callParentScopePackage = newScope { };

        # TODO: Override makeScopeWithSplicing, makeScopeWithSplicing', __splicedPackages?
        # TODO: Override `pkgsCross`?
      };
    in
    self;

  # Adapted from https://github.com/NixOS/nixpkgs/blob/3378e4ec169425e7434d101f32680c068799a0f4/lib/customisation.nix
  # Changes:
  #  - Include own splices in `self`
  #  - Include merged splices in `newScope`
  makeScopeWithSplicing' =
    { splicePackages
    , newScope
    }:
    { otherSplices
    , keep ? (_self: { })
    , extra ? (_spliced0: { })
    , f
    }:
    let
      baseSplices = newScopeSplices newScope;
      selfSplices = {
        pkgsBuildBuild = otherSplices.selfBuildBuild;
        pkgsBuildHost = otherSplices.selfBuildHost;
        pkgsBuildTarget = otherSplices.selfBuildTarget;
        pkgsHostHost = otherSplices.selfHostHost;
        pkgsHostTarget = self; # Not `otherSplices.selfHostTarget`;
        pkgsTargetTarget = otherSplices.selfTargetTarget;
      };

      spliced0 = splicePackages selfSplices;
      spliced = extra spliced0 // spliced0 // mergeSplices baseSplices selfSplices // keep self;
      self = f self // selfSplices // {
        newScope = scope: newScope (spliced // scope);
        callPackage = newScope spliced;
        overrideScope = g: (makeScopeWithSplicing'
          { inherit splicePackages newScope; }
          {
            inherit otherSplices keep extra;
            f = lib.extends g f;
          });
        packages = f;

        # TODO: Not sure if this is a good idea, but it's convenient for avoiding infinite
        # recursion or accessing shadowed packages.
        callParentScopePackage = newScope { };

        # TODO: Override makeScopeWithSplicing, makeScopeWithSplicing', __splicedPackages?
        # TODO: Override `pkgsCross`?
      };
    in
    self;

  makeScopeWithSplicing =
    splicePackages: newScope: otherSplices: keep: extra: f:
    makeScopeWithSplicing'
      { inherit splicePackages newScope; }
      { inherit otherSplices keep extra f; };
in
{
  inherit
    makeScope
    makeScopeWithSplicing
    makeScopeWithSplicing';
}
