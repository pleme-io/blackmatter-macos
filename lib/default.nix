# Blackmatter macOS — Unified Library API
#
# Single-import entry point for all macOS build helpers.
# Follows the substrate lib/default.nix pattern.
#
# Usage:
#   macosLib = import "${blackmatter-macos}/lib" { inherit lib; };
#   macosLib.mkSwiftPackage pkgs { ... }
#   macosLib.mkSwiftApp pkgs { ... }
#   macosLib.codesign.adHocSign { path = ...; }
{ lib }:

let
  overlayModule = import ./overlay.nix;
  sdkHelpers = import ./sdk-helpers.nix { inherit lib; };
  sandbox = import ./sandbox.nix { inherit lib; };
  codesign = import ./codesign.nix { inherit lib; };
  swiftPackageModule = import ./swift-package.nix { inherit lib; };
  swiftAppModule = import ./swift-app.nix { inherit lib; };
  zigSwiftAppModule = import ./zig-swift-app.nix { inherit lib; };
  xcodeProjectModule = import ./xcode-project.nix { inherit lib; };
in {
  # ── Overlay ──────────────────────────────────────────────────────
  inherit (overlayModule) mkSwiftOverlay;

  # ── SDK & Sandbox ────────────────────────────────────────────────
  inherit sdkHelpers sandbox;

  # ── Codesigning ──────────────────────────────────────────────────
  inherit codesign;

  # ── Build Helpers ────────────────────────────────────────────────
  inherit (swiftPackageModule) mkSwiftPackage;
  inherit (swiftAppModule) mkSwiftApp;
  inherit (zigSwiftAppModule) mkZigSwiftApp;
  inherit (xcodeProjectModule) mkXcodeProject;
}
