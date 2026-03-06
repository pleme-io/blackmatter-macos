# blackmatter-macos

Swift toolchain, Apple SDK helpers, codesigning, and build patterns for native macOS apps.

## Overview

Darwin-only Nix library providing a from-source Swift toolchain overlay, Xcode project helpers, sandbox entitlement generation, codesigning utilities, and the `mkZigSwiftApp` build pattern for hybrid Zig+Swift applications. Used by blackmatter-ghostty and other macOS native builds. Includes a home-manager module for installing the Swift toolchain in the user environment.

## Flake Outputs

- `overlays.default` -- Swift toolchain overlay (`pkgs.swiftToolchain`, `pkgs.mkZigSwiftApp`)
- `packages.<system>.swift` -- Swift toolchain (Darwin only)
- `homeManagerModules.default` -- HM module at `blackmatter.components.macos`
- `lib` -- standalone import paths for all build helpers
- `tests`, `checks` -- pure Nix eval unit tests

## Usage

```nix
{
  inputs.blackmatter-macos.url = "github:pleme-io/blackmatter-macos";
}
```

```nix
overlays = [ blackmatter-macos.overlays.default ];
```

## Lib Exports

- `overlay.nix` -- `mkSwiftOverlay` factory
- `swift-package.nix` -- SwiftPM package builder
- `swift-app.nix` -- Swift application builder
- `zig-swift-app.nix` -- hybrid Zig+Swift application builder
- `xcode-project.nix` -- Xcode project builder
- `sdk-helpers.nix` -- Apple SDK path resolution
- `sandbox.nix` -- sandbox entitlement generation
- `codesign.nix` -- ad-hoc codesigning
- `completions.nix` -- shell completion generation
- `swift-tool-release.nix` -- release artifact builder

## Structure

- `lib/` -- all build pattern implementations
- `module/` -- home-manager module
- `tests/` -- pure Nix eval unit tests
