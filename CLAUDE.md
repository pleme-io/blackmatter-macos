# blackmatter-macos — Claude Orientation

> **★★★ CSE / Knowable Construction.** This repo operates under **Constructive Substrate Engineering** — canonical specification at [`pleme-io/theory/CONSTRUCTIVE-SUBSTRATE-ENGINEERING.md`](https://github.com/pleme-io/theory/blob/main/CONSTRUCTIVE-SUBSTRATE-ENGINEERING.md). The Compounding Directive (operational rules: solve once, load-bearing fixes only, idiom-first, models stay current, direction beats velocity) is in the org-level pleme-io/CLAUDE.md ★★★ section. Read both before non-trivial changes.


One-sentence purpose: Darwin-only Swift toolchain overlay + Apple SDK helpers +
code-signing / sandbox utilities, plus direct-importable builders for Swift/Xcode apps.

## Classification

- **Archetype:** `blackmatter-component-custom-darwin-overlay`
- **Flake shape:** **custom** (does NOT go through mkBlackmatterFlake)
- **Reason:** Darwin-only, overlay + `lib/` import surface + build-pattern exports
  (`swiftPackage`, `swiftApp`, `zigSwiftApp`, `xcodeProject`, `swiftToolRelease`).
  Template covers cross-platform module repos, not build-pattern libraries.
- **Systems:** `x86_64-darwin`, `aarch64-darwin` only.

## Where to look

| Intent | File |
|--------|------|
| Swift toolchain overlay | `lib/overlay.nix` |
| Swift bootstrap | `lib/swift/bootstrap.nix` |
| Code-signing helper | `lib/codesign.nix` |
| Sandbox helper | `lib/sandbox.nix` |
| App builders | `lib/swift-app.nix`, `lib/zig-swift-app.nix`, `lib/swift-tool-release.nix` |
| HM module | `module/default.nix` |
| Unit tests | `tests/` |

## Tests

- `nix flake check` runs the `unit` check which executes the pure-eval test
  suite in `tests/` (no VM needed).

## What NOT to do

- Don't add Linux systems. This is Darwin-only by design.
- Don't break the impure-build patterns — downstream consumers (ghostty,
  namimado, aranami) depend on them.
