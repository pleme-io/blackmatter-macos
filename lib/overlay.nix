# Swift Overlay Module
#
# CANONICAL SOURCE: substrate (github:pleme-io/substrate)
# Keep in sync — direct file imports from consumers still use these paths.
#
# Provides a reusable Swift overlay with prebuilt toolchain from swift.org.
#
# Usage:
#   swiftOverlay = import "${blackmatter-macos}/lib/overlay.nix";
#   pkgs = import nixpkgs {
#     inherit system;
#     overlays = [ (swiftOverlay.mkSwiftOverlay {}) ];
#   };
#
# The overlay provides:
#   - pkgs.swiftToolchain — prebuilt Swift compiler from swift.org
#   - pkgs.swift6 — alias for the toolchain
#   - pkgs.mkSwiftPackage — build SPM packages (from blackmatter-macos)
#   - pkgs.mkSwiftApp — build .app bundles (from blackmatter-macos)
#   - pkgs.mkZigSwiftApp — build Zig+Swift apps (from blackmatter-macos)
#   - pkgs.mkXcodeProject — build .xcodeproj (from blackmatter-macos)
{
  # Create a Swift overlay with prebuilt toolchain from swift.org.
  #
  # Returns: An overlay function (final: prev: ...)
  mkSwiftOverlay = {}: final: prev: let
    swiftToolchain = prev.callPackage ./swift/bootstrap.nix {};
    macosLib = import ./default.nix { lib = prev.lib; };
  in {
    inherit swiftToolchain;
    swift6 = swiftToolchain;

    # Build helpers — exposed as pkgs.mkSwift* for convenience
    mkSwiftPackage = macosLib.mkSwiftPackage final;
    mkSwiftApp = macosLib.mkSwiftApp final;
    mkZigSwiftApp = macosLib.mkZigSwiftApp final;
    mkXcodeProject = macosLib.mkXcodeProject final;
  };
}
