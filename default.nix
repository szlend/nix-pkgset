{ lib }:

let
  getScopeSplices = newScope: newScope { }
    ({ pkgsBuildBuild
     , pkgsBuildHost
     , pkgsBuildTarget
     , pkgsHostHost
     , pkgsHostTarget
     , pkgsTargetTarget
     } @ splices: splices)
    { };

  makeSelfSplices = pkgs: f: {
    # TODO: Optimization: Some `pkgs<host><target>` package sets are equivalent.
    # There's probably a better way to initialize this that avoids recursive re-evaluation
    # when you do `pkgsBuildBuild.pkgsBuildBuild`.
    selfBuildBuild = makePackageSet pkgs.pkgsBuildBuild f;
    selfBuildHost = makePackageSet pkgs.pkgsBuildHost f;
    selfBuildTarget = makePackageSet pkgs.pkgsBuildTarget f;
    selfHostHost = makePackageSet pkgs.pkgsHostHost f;
    selfHostTarget = makePackageSet pkgs.pkgsHostTarget f;
    selfTargetTarget = lib.optionalAttrs (pkgs.pkgsTargetTarget?newScope) (makePackageSet pkgs.pkgsTargetTarget f);
  };

  mergeSplices = a: b: rec {
    pkgsBuildBuild = makePackageSet a.pkgsBuildBuild (_self: a.pkgsBuildBuild // b.pkgsBuildBuild);
    pkgsBuildHost = makePackageSet a.pkgsBuildHost (_self: a.pkgsBuildHost // b.pkgsBuildHost);
    pkgsBuildTarget = makePackageSet a.pkgsBuildTarget (_self: a.pkgsBuildTarget // b.pkgsBuildTarget);
    pkgsHostHost = makePackageSet a.pkgsHostHost (_self: a.pkgsHostHost // b.pkgsHostHost);
    pkgsHostTarget = makePackageSet a.pkgsHostTarget (_self: a.pkgsHostTarget // b.pkgsHostTarget);
    pkgsTargetTarget =
      let merged = lib.optionalAttrs (a.pkgsTargetTarget?newScope) a.pkgsTargetTarget // lib.optionalAttrs (b.pkgsTargetTarget?newScope) b.pkgsTargetTarget;
      in lib.optionalAttrs (merged?newScope) (makePackageSet merged (_self: merged));

    buildPackages = pkgsBuildHost;
    pkgs = pkgsHostTarget;
    targetPackages = pkgsTargetTarget;
  };

  # Adapted from https://github.com/NixOS/nixpkgs/blob/3378e4ec169425e7434d101f32680c068799a0f4/lib/customisation.nix
  # Changes:
  #  - Include self splices in `self`
  #  - Include merged splices in `newScope`
  #  - Include `callParentScopePackage`
  #  - Override makeScopeWithSplicing/makeScopeWithSplicing'
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
      baseSplices = getScopeSplices newScope;
      selfSplices = {
        pkgsBuildBuild = otherSplices.selfBuildBuild;
        pkgsBuildHost = otherSplices.selfBuildHost;
        pkgsBuildTarget = otherSplices.selfBuildTarget;
        pkgsHostHost = otherSplices.selfHostHost;
        pkgsHostTarget = self; # Not `otherSplices.selfHostTarget`;
        pkgsTargetTarget = otherSplices.selfTargetTarget;
      };

      spliced0 = splicePackages selfSplices // mergeSplices baseSplices selfSplices;
      spliced = extra spliced0 // spliced0 // keep self;
      self = f self // selfSplices // {
        newScope = scope: newScope (spliced // scope);
        callPackage = newScope spliced;
        overrideScope = g: (makeScopeWithSplicing'
          { inherit splicePackages newScope; }
          { inherit otherSplices keep extra; f = lib.extends g f; });
        packages = f;

        makeScopeWithSplicing' = makeScopeWithSplicing' { inherit splicePackages; newScope = self.newScope; };
        makeScopeWithSplicing = makeScopeWithSplicing splicePackages self.newScope;

        # TODO: Not sure if this is a good idea, but it's convenient for avoiding infinite
        # recursion or accessing shadowed packages.
        callParentScopePackage = newScope { };
        # TODO: Override `pkgsCross`, `pkgsLLVM`, etc?
      };
    in
    self;

  makeScopeWithSplicing =
    splicePackages: newScope: otherSplices: keep: extra: f:
    makeScopeWithSplicing'
      { inherit splicePackages newScope; }
      { inherit otherSplices keep extra f; };

  makePackageSet = pkgs: f:
    makeScopeWithSplicing'
      { inherit (pkgs) splicePackages newScope; }
      { inherit f; otherSplices = makeSelfSplices pkgs f; };

  mergePackageSets = pkgsets:
    let
      pkgsMerged = lib.foldl' (acc: pkgset: acc // pkgset) { } pkgsets;
      f = (_self: pkgsMerged);
      # TODO: Use `__splicedPackages` to skip splicing twice.
    in
    makePackageSet pkgsMerged f;

  packageSetFromOverlay = pkgs: overlay:
    let
      attrs = lib.attrNames (overlay pkgs pkgs);
      applyOverlay = pkgs: lib.fix (lib.extends overlay (_self: pkgs));
    in
    # Using `callParentPackage` here to avoid infinite recursion.
    makePackageSet pkgs (self:
      lib.getAttrs attrs (self.callParentScopePackage ({ pkgsHostTarget }: applyOverlay pkgsHostTarget) { }));
in
{
  inherit
    makePackageSet
    mergePackageSets
    packageSetFromOverlay;
}
