# ============================================================================
# SWIFT TOOL RELEASE BUILDER - Darwin-only CLI tool builds + GitHub releases
# ============================================================================
# Builds a Swift CLI tool for both Darwin targets using Swift Package Manager.
# Darwin-only — Swift toolchain requires macOS. Both architectures build on
# any Darwin host (x86_64 via Rosetta on aarch64).
#
# Targets:
#   - aarch64-macos  (native or Rosetta)
#   - x86_64-macos   (native or Rosetta)
#
# Usage:
#   let swiftTool = import "${blackmatter-macos}/lib/swift-tool-release.nix" {
#     inherit nixpkgs system substrate;
#   };
#   in swiftTool {
#     toolName = "my-tool";
#     src = self;
#     repo = "myorg/my-tool";
#   }
#
# Returns: { packages, devShells, apps }
{
  nixpkgs,
  system,
  substrate,
}: let
  swiftOverlay = (import ./overlay.nix).mkSwiftOverlay {};

  hostPkgs = import nixpkgs {
    inherit system;
    overlays = [ swiftOverlay ];
  };
  lib = hostPkgs.lib;

  swiftPkgLib = import ./swift-package.nix { inherit lib; };
  completionsLib = import ./completions.nix;

  # ============================================================================
  # DARWIN CROSS-COMPILATION TARGETS
  # ============================================================================
  # Both architectures are available on any Darwin host.
  # On aarch64-darwin, x86_64 builds via Rosetta translation.
  # On x86_64-darwin, aarch64 builds require an aarch64-darwin builder.

  targets = {
    "aarch64-macos" = "aarch64-darwin";
    "x86_64-macos" = "x86_64-darwin";
  };

  # ============================================================================
  # RELEASE HELPERS (from substrate)
  # ============================================================================
  releaseHelpers = import "${substrate}/lib/release-helpers.nix";
in {
  toolName,
  src,
  repo,
  version ? "1.0.0",
  swiftFlags ? [],
  buildConfiguration ? "release",
  extraBuildInputs ? [],
  products ? [ toolName ],
  completions ? null,
  ...
}:
let
  # ============================================================================
  # BINARY BUILDERS
  # ============================================================================

  # Build for a specific target system
  mkTargetBinary = releaseName: targetSystem: let
    targetPkgs = import nixpkgs {
      system = targetSystem;
      overlays = [ swiftOverlay ];
    };
    completionAttrs = completionsLib.mkSwiftCompletionAttrs targetPkgs {
      pname = toolName;
      inherit completions;
    };
  in swiftPkgLib.mkSwiftPackage targetPkgs {
    pname = "${toolName}-${releaseName}";
    inherit version src swiftFlags buildConfiguration products;
    extraBuildInputs = extraBuildInputs ++ completionAttrs.nativeBuildInputs;
    postInstall = completionAttrs.postInstallScript;
  };

  # Build all target binaries
  binaries = lib.mapAttrs mkTargetBinary targets;

  # Native binary (uses host system directly)
  nativeCompletionAttrs = completionsLib.mkSwiftCompletionAttrs hostPkgs {
    pname = toolName;
    inherit completions;
  };

  nativeBinary = swiftPkgLib.mkSwiftPackage hostPkgs {
    pname = toolName;
    inherit version src swiftFlags buildConfiguration products;
    extraBuildInputs = extraBuildInputs ++ nativeCompletionAttrs.nativeBuildInputs;
    postInstall = nativeCompletionAttrs.postInstallScript;
  };

  # ============================================================================
  # APPS (via substrate release-helpers.nix)
  # ============================================================================
  releaseApp = releaseHelpers.mkReleaseApp {
    inherit hostPkgs toolName repo;
    language = "swift";
  };

  bumpApp = releaseHelpers.mkBumpApp {
    inherit hostPkgs toolName;
    language = "swift";
  };

  checkAllApp = releaseHelpers.mkCheckAllApp {
    inherit hostPkgs toolName;
    language = "swift";
  };
in {
  packages = lib.mapAttrs' (releaseName: binary: {
    name = "${toolName}-${releaseName}";
    value = binary;
  }) binaries // {
    default = nativeBinary;
    ${toolName} = nativeBinary;
  };

  devShells.default = hostPkgs.mkShell {
    buildInputs = [
      hostPkgs.swiftToolchain
    ] ++ extraBuildInputs;
  };

  apps = {
    default = {
      type = "app";
      program = "${nativeBinary}/bin/${toolName}";
    };
    release = releaseApp;
    bump = bumpApp;
    check-all = checkAllApp;
  };
}
