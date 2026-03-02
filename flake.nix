{
  description = "Blackmatter macOS — Swift toolchain, Apple SDK helpers, codesigning, and build patterns for native macOS apps";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    substrate = {
      url = "github:pleme-io/substrate";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    blackmatter-zig = {
      url = "github:pleme-io/blackmatter-zig";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.substrate.follows = "substrate";
    };
  };

  outputs = { self, nixpkgs, substrate, blackmatter-zig }:
  let
    lib = nixpkgs.lib;

    # Darwin-only — Swift toolchain is macOS-specific
    darwinSystems = [ "x86_64-darwin" "aarch64-darwin" ];

    forEachDarwin = f: lib.genAttrs darwinSystems (system: f {
      inherit system;
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          self.overlays.default
          blackmatter-zig.overlays.default
        ];
      };
    });

    testHelpers = import "${substrate}/lib/test-helpers.nix" { inherit lib; };
  in {
    # ── Overlay ─────────────────────────────────────────────────────
    overlays.default = (import ./lib/overlay.nix).mkSwiftOverlay {};

    # ── Packages ────────────────────────────────────────────────────
    packages = forEachDarwin ({ pkgs, ... }: {
      default = pkgs.swiftToolchain;
      swift = pkgs.swiftToolchain;
    });

    # ── Home-Manager Module ─────────────────────────────────────────
    homeManagerModules.default = import ./module;

    # ── Lib exports (standalone import paths) ───────────────────────
    lib = {
      overlay = ./lib/overlay.nix;
      bootstrap = ./lib/swift/bootstrap.nix;
      sdkHelpers = ./lib/sdk-helpers.nix;
      sandbox = ./lib/sandbox.nix;
      codesign = ./lib/codesign.nix;
      completions = ./lib/completions.nix;
      swiftPackage = ./lib/swift-package.nix;
      swiftApp = ./lib/swift-app.nix;
      zigSwiftApp = ./lib/zig-swift-app.nix;
      xcodeProject = ./lib/xcode-project.nix;
      swiftToolRelease = ./lib/swift-tool-release.nix;
    };

    # ── Tests (pure Nix eval — no builds) ───────────────────────────
    tests = forEachDarwin ({ ... }: {
      unit = import ./tests {
        inherit lib testHelpers;
      };
    });

    # ── Checks ──────────────────────────────────────────────────────
    checks = forEachDarwin ({ pkgs, system, ... }: let
      testResults = self.tests.${system}.unit;
    in {
      # Pure eval test: all lib functions produce correct results
      unit = pkgs.runCommand "blackmatter-macos-unit-tests" {} (
        if testResults.allPassed
        then ''echo "${testResults.summary}" > $out''
        else builtins.throw (
          "blackmatter-macos unit tests failed (${testResults.summary}):\n"
          + lib.concatStringsSep "\n" testResults.failures
        )
      );
    });
  };
}
