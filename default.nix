{ lib }:

let
  getScopeSplices = newScope: newScope { }
    ({ pkgsBuildBuild
     , pkgsBuildHost
     , pkgsBuildTarget
     , pkgsHostHost
     , pkgsHostTarget
     , pkgsTargetTarget
     , pkgsCross
     , pkgsLLVM
     , pkgsMusl
     , pkgsi686Linux
     , pkgsx86_64Darwin
     , pkgsStatic
     , pkgsExtraHardening
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

  mergeExtraPackageSets = a: b: {
    pkgsCross = lib.mapAttrs
      (name: _crossSystem: makePackageSet a.pkgsCross.${name} (_self: a.pkgsCross.${name} // b.pkgsCross.${name}))
      lib.systems.examples;
    pkgsLLVM = makePackageSet a.pkgsLLVM (_self: a.pkgsLLVM // b.pkgsLLVM);
    pkgsMusl = makePackageSet a.pkgsMusl (_self: a.pkgsMusl // b.pkgsMusl);
    pkgsi686Linux = makePackageSet a.pkgsi686Linux (_self: a.pkgsi686Linux // b.pkgsi686Linux);
    pkgsx86_64Darwin = makePackageSet a.pkgsx86_64Darwin (_self: a.pkgsx86_64Darwin // b.pkgsx86_64Darwin);
    pkgsStatic = makePackageSet a.pkgsStatic (_self: a.pkgsStatic // b.pkgsStatic);
    pkgsExtraHardening = makePackageSet a.pkgsExtraHardening (_self: a.pkgsExtraHardening // b.pkgsExtraHardening);
  };

  # Adapted from https://github.com/NixOS/nixpkgs/blob/3378e4ec169425e7434d101f32680c068799a0f4/lib/customisation.nix
  # Changes:
  #  - Include self splices and self extra package sets in `self`
  #  - Include merged splices and merged extra package sets in `newScope`
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
      selfExtraPackageSets = {
        pkgsCross = lib.mapAttrs
          (name: _crossSystem: makePackageSet baseSplices.pkgsCross.${name} f)
          lib.systems.examples;
        pkgsLLVM = makePackageSet baseSplices.pkgsLLVM f;
        pkgsMusl = makePackageSet baseSplices.pkgsMusl f;
        pkgsi686Linux = makePackageSet baseSplices.pkgsi686Linux f;
        pkgsx86_64Darwin = makePackageSet baseSplices.pkgsx86_64Darwin f;
        pkgsStatic = makePackageSet baseSplices.pkgsStatic f;
        pkgsExtraHardening = makePackageSet baseSplices.pkgsExtraHardening f;
      };

      spliced0 = splicePackages selfSplices // mergeSplices baseSplices selfSplices // mergeExtraPackageSets baseSplices selfSplices;
      spliced = extra spliced0 // spliced0 // keep self;
      self = f self // selfSplices // selfExtraPackageSets // {
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
        # TODO: `pkgs.appendOverlays`
        # TODO: `pkgs.extend`
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
