{ lib }:

let
  # Shift `otherSplices` depending on `host` and `target`.
  mapSplices = otherSplices: host: target: {
    selfBuildBuild = otherSplices."selfBuildBuild";
    selfBuildHost = otherSplices."selfBuild${host}";
    selfBuildTarget = otherSplices."selfBuild${target}";
    selfHostHost = otherSplices."self${host}${host}";
    selfHostTarget = otherSplices."self${host}${target}";
    selfTargetTarget = otherSplices."self${target}${target}";
  };

  makePackageSet =
    name: newScope: f: otherSplices':
    let
      callPackage = newScope { };
      prev = callPackage (
        {
          # Fetch the splicing function from the base scope.
          splicePackages,
          # Fetch splices from the base scope. If the base scope is `nixpkgs`,
          # these will be under `pkgs.*`, otherwise under `__splices.*`.
          pkgs,
          __splices ? {
            selfBuildBuild = pkgs.pkgsBuildBuild;
            selfBuildHost = pkgs.pkgsBuildHost;
            selfBuildTarget = pkgs.pkgsBuildTarget;
            selfHostHost = pkgs.pkgsHostHost;
            selfHostTarget = pkgs.pkgsHostTarget;
            selfTargetTarget = pkgs.pkgsTargetTarget;
          },
        }:
        __splices // { inherit splicePackages; }
      ) { };

      # Evaluate the scope function `f` under different splices. Avoid re-evaluating
      # splices recursively by remapping them back to root `otherSplices`.
      defaultOtherSplices = {
        selfBuildBuild = makePackageSet name prev.selfBuildBuild.newScope f (
          mapSplices defaultOtherSplices "Build" "Build"
        );
        selfBuildHost = makePackageSet name prev.selfBuildHost.newScope f (
          mapSplices defaultOtherSplices "Build" "Host"
        );
        selfBuildTarget = makePackageSet name prev.selfBuildTarget.newScope f (
          mapSplices defaultOtherSplices "Build" "Target"
        );
        selfHostHost = makePackageSet name prev.selfHostHost.newScope f (
          mapSplices defaultOtherSplices "Host" "Host"
        );
        selfHostTarget = makePackageSet name prev.selfHostTarget.newScope f (
          mapSplices defaultOtherSplices "Host" "Target"
        );
        selfTargetTarget = lib.optionalAttrs (prev.selfTargetTarget ? "newScope") (
          makePackageSet name prev.selfTargetTarget.newScope f (
            mapSplices defaultOtherSplices "Target" "Target"
          )
        );
      };

      # If `otherSplices'` have already been defined for us, prefer them instead.
      otherSplices = lib.defaultTo defaultOtherSplices otherSplices';

      makeScopeWithSplicing' = lib.makeScopeWithSplicing' {
        inherit newScope;
        inherit (prev) splicePackages;
      };
    in
    makeScopeWithSplicing' {
      inherit otherSplices;
      f =
        self:
        f self
        // {
          # Spliced package set, equivalent to `pkgs.__splicedPackages`.
          "${name}" = self.callPackage ({ __spliced }: __spliced) { };
          # Other named splices, equivalent to `pkgs.pkgs<host><target>`.
          "${name}BuildBuild" = otherSplices.selfBuildBuild;
          "${name}BuildHost" = otherSplices.selfBuildHost;
          "${name}BuildTarget" = otherSplices.selfBuildTarget;
          "${name}HostHost" = otherSplices.selfHostHost;
          "${name}HostTarget" = self;
          "${name}TargetTarget" = otherSplices.selfTargetTarget;
          # Rename `packages` to `scopeFn` as it conflicts with flake schema.
          scopeFn = self.packages;
        };
      extra = spliced: {
        # Include the spliced package set which we re-export above as `${name}`.
        __spliced = spliced;
        # Include other splices. These are used when making a new scope based on this one.
        __splices = otherSplices;
      };
      # Keep these sets as they are, don't splice them.
      keep = self: {
        "${name}" = self."${name}";
        "${name}BuildBuild" = self."${name}BuildBuild";
        "${name}BuildHost" = self."${name}BuildHost";
        "${name}BuildTarget" = self."${name}BuildTarget";
        "${name}HostHost" = self."${name}HostHost";
        "${name}HostTarget" = self."${name}HostTarget";
        "${name}TargetTarget" = self."${name}TargetTarget";
      };
    };
in
{
  makePackageSet =
    name: newScope: f:
    # Remove the `packages` attribute as it conflicts with flake schema.
    builtins.removeAttrs (makePackageSet name newScope f null) [ "packages" ];
}
