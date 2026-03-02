# Pure Nix evaluation tests for blackmatter-macos
#
# Tests all library functions via pure eval — no builds, instant results.
# Run: nix eval .#tests.<system>.unit --json | jq
{ lib, testHelpers }:

let
  inherit (testHelpers) mkTest runTests;

  # ── Import all library modules ──────────────────────────────────────
  codesignLib = import ../lib/codesign.nix { inherit lib; };
  sdkHelpers = import ../lib/sdk-helpers.nix { inherit lib; };
  sandbox = import ../lib/sandbox.nix { inherit lib; };
  swiftPkgLib = import ../lib/swift-package.nix { inherit lib; };
  swiftAppLib = import ../lib/swift-app.nix { inherit lib; };
  zigSwiftLib = import ../lib/zig-swift-app.nix { inherit lib; };
  xcodeProjLib = import ../lib/xcode-project.nix { inherit lib; };
  overlayLib = import ../lib/overlay.nix;
  macosLib = import ../lib/default.nix { inherit lib; };

  # ── Mock pkgs for build helper tests ────────────────────────────────
  # mkDerivation returns the attrs it receives — lets us inspect build phases
  mockPkgs = {
    stdenv = {
      hostPlatform.isDarwin = true;
      mkDerivation = attrs: attrs;
    };
    stdenvNoCC = {
      mkDerivation = attrs: attrs;
    };
    swiftToolchain = "/nix/store/mock-swift-toolchain";
    swift = "/nix/store/mock-swift";
    zigToolchain = "/nix/store/mock-zig-toolchain";
    apple-sdk = "/nix/store/mock-apple-sdk";
    writeText = name: content: "/nix/store/mock-${name}";
  };

  # Mock pkgs with old-style darwin.apple_sdk (no apple-sdk attr)
  mockPkgsOldSDK = {
    darwin.apple_sdk.frameworks = {
      Foundation = "mock-Foundation";
      AppKit = "mock-AppKit";
      Security = "mock-Security";
      SystemConfiguration = "mock-SystemConfiguration";
    };
  };

  # Mock pkgs with neither apple-sdk nor darwin (minimal)
  mockPkgsMinimal = {};

  # ══════════════════════════════════════════════════════════════════════
  # codesign.nix tests (22 + 10 = 32)
  # ══════════════════════════════════════════════════════════════════════
  codesignTests = [
    # ── adHocSign ──
    (mkTest "codesign-adHocSign-returns-string"
      (builtins.isString (codesignLib.adHocSign { path = "/tmp/test"; }))
      "adHocSign should return a string")

    (mkTest "codesign-adHocSign-contains-codesign"
      (lib.hasInfix "/usr/bin/codesign" (codesignLib.adHocSign { path = "/tmp/test"; }))
      "adHocSign should call /usr/bin/codesign")

    (mkTest "codesign-adHocSign-contains-path"
      (lib.hasInfix "/tmp/test" (codesignLib.adHocSign { path = "/tmp/test"; }))
      "adHocSign should include the target path")

    (mkTest "codesign-adHocSign-force-flag"
      (lib.hasInfix "-f" (codesignLib.adHocSign { path = "/tmp/test"; }))
      "adHocSign should always include -f (force) flag")

    (mkTest "codesign-adHocSign-adhoc-identity"
      (lib.hasInfix "-s -" (codesignLib.adHocSign { path = "/tmp/test"; }))
      "adHocSign should use ad-hoc identity (-s -)")

    (mkTest "codesign-adHocSign-error-suppression"
      (lib.hasInfix "2>/dev/null || true" (codesignLib.adHocSign { path = "/tmp/test"; }))
      "adHocSign should suppress errors gracefully")

    (mkTest "codesign-adHocSign-deep-flag"
      (lib.hasInfix "--deep" (codesignLib.adHocSign { path = "/tmp/test"; deep = true; }))
      "adHocSign with deep=true should include --deep")

    (mkTest "codesign-adHocSign-no-deep-by-default"
      (!(lib.hasInfix "--deep" (codesignLib.adHocSign { path = "/tmp/test"; })))
      "adHocSign should not include --deep by default")

    (mkTest "codesign-adHocSign-entitlements-flag"
      (lib.hasInfix "--entitlements" (codesignLib.adHocSign {
        path = "/tmp/test";
        entitlements = "/tmp/ent.plist";
      }))
      "adHocSign with entitlements should include --entitlements")

    (mkTest "codesign-adHocSign-entitlements-path"
      (lib.hasInfix "/tmp/ent.plist" (codesignLib.adHocSign {
        path = "/tmp/test";
        entitlements = "/tmp/ent.plist";
      }))
      "adHocSign with entitlements should include the entitlements path")

    (mkTest "codesign-adHocSign-no-entitlements-by-default"
      (!(lib.hasInfix "--entitlements" (codesignLib.adHocSign { path = "/tmp/test"; })))
      "adHocSign should not include --entitlements by default")

    # ── mkEntitlements ──
    (mkTest "codesign-mkEntitlements-returns-string"
      (builtins.isString (codesignLib.mkEntitlements {}))
      "mkEntitlements should return a string")

    (mkTest "codesign-mkEntitlements-valid-plist-header"
      (lib.hasInfix "<?xml version" (codesignLib.mkEntitlements {}))
      "mkEntitlements should produce XML plist header")

    (mkTest "codesign-mkEntitlements-dtd-doctype"
      (lib.hasInfix "<!DOCTYPE plist" (codesignLib.mkEntitlements {}))
      "mkEntitlements should include DTD DOCTYPE declaration")

    (mkTest "codesign-mkEntitlements-plist-dict"
      (lib.hasInfix "<dict>" (codesignLib.mkEntitlements {}))
      "mkEntitlements should contain <dict> element")

    (mkTest "codesign-mkEntitlements-closing-plist"
      (lib.hasInfix "</plist>" (codesignLib.mkEntitlements {}))
      "mkEntitlements should have closing </plist> tag")

    (mkTest "codesign-mkEntitlements-closing-dict"
      (lib.hasInfix "</dict>" (codesignLib.mkEntitlements {}))
      "mkEntitlements should have closing </dict> tag")

    (mkTest "codesign-mkEntitlements-jit"
      (lib.hasInfix "com.apple.security.cs.allow-jit" (codesignLib.mkEntitlements { allowJit = true; }))
      "mkEntitlements with allowJit should include JIT key")

    (mkTest "codesign-mkEntitlements-no-jit-by-default"
      (!(lib.hasInfix "com.apple.security.cs.allow-jit" (codesignLib.mkEntitlements {})))
      "mkEntitlements should not include JIT key by default")

    (mkTest "codesign-mkEntitlements-disable-lib-validation"
      (lib.hasInfix "com.apple.security.cs.disable-library-validation"
        (codesignLib.mkEntitlements { disableLibraryValidation = true; }))
      "mkEntitlements with disableLibraryValidation should include the key")

    (mkTest "codesign-mkEntitlements-no-lib-validation-by-default"
      (!(lib.hasInfix "com.apple.security.cs.disable-library-validation"
        (codesignLib.mkEntitlements {})))
      "mkEntitlements should not include disable-library-validation by default")

    (mkTest "codesign-mkEntitlements-app-sandbox"
      (lib.hasInfix "com.apple.security.app-sandbox"
        (codesignLib.mkEntitlements { appSandbox = true; }))
      "mkEntitlements with appSandbox should include sandbox key")

    (mkTest "codesign-mkEntitlements-network-client"
      (lib.hasInfix "com.apple.security.network.client"
        (codesignLib.mkEntitlements { networkClient = true; }))
      "mkEntitlements with networkClient should include network.client key")

    (mkTest "codesign-mkEntitlements-network-server"
      (lib.hasInfix "com.apple.security.network.server"
        (codesignLib.mkEntitlements { networkServer = true; }))
      "mkEntitlements with networkServer should include network.server key")

    (mkTest "codesign-mkEntitlements-file-read"
      (lib.hasInfix "files.user-selected.read-only"
        (codesignLib.mkEntitlements { fileReadAccess = true; }))
      "mkEntitlements with fileReadAccess should include read-only key")

    (mkTest "codesign-mkEntitlements-file-write"
      (lib.hasInfix "files.user-selected.read-write"
        (codesignLib.mkEntitlements { fileWriteAccess = true; }))
      "mkEntitlements with fileWriteAccess should include read-write key")

    (mkTest "codesign-mkEntitlements-all-enabled"
      (let ent = codesignLib.mkEntitlements {
        allowJit = true;
        disableLibraryValidation = true;
        appSandbox = true;
        networkClient = true;
        networkServer = true;
        fileReadAccess = true;
        fileWriteAccess = true;
      }; in
        lib.hasInfix "allow-jit" ent
        && lib.hasInfix "disable-library-validation" ent
        && lib.hasInfix "app-sandbox" ent
        && lib.hasInfix "network.client" ent
        && lib.hasInfix "network.server" ent
        && lib.hasInfix "read-only" ent
        && lib.hasInfix "read-write" ent)
      "mkEntitlements with all options should include all keys")

    (mkTest "codesign-mkEntitlements-true-tags"
      (let ent = codesignLib.mkEntitlements { allowJit = true; }; in
        lib.hasInfix "<true/>" ent)
      "mkEntitlements enabled keys should have <true/> values")

    # ── signAllMachO ──
    (mkTest "codesign-signAllMachO-returns-string"
      (builtins.isString (codesignLib.signAllMachO { path = "/tmp/app"; }))
      "signAllMachO should return a string")

    (mkTest "codesign-signAllMachO-uses-file-command"
      (lib.hasInfix "/usr/bin/file" (codesignLib.signAllMachO { path = "/tmp/app"; }))
      "signAllMachO should use /usr/bin/file to detect Mach-O")

    (mkTest "codesign-signAllMachO-uses-find"
      (lib.hasInfix "find" (codesignLib.signAllMachO { path = "/tmp/app"; }))
      "signAllMachO should use find to walk directory")

    (mkTest "codesign-signAllMachO-detects-macho"
      (lib.hasInfix "Mach-O" (codesignLib.signAllMachO { path = "/tmp/app"; }))
      "signAllMachO should grep for Mach-O signature")

    (mkTest "codesign-signAllMachO-chmod-pattern"
      (lib.hasInfix "chmod u+w" (codesignLib.signAllMachO { path = "/tmp/app"; }))
      "signAllMachO should chmod u+w before signing")

    (mkTest "codesign-signAllMachO-restore-perms"
      (lib.hasInfix "chmod u-w" (codesignLib.signAllMachO { path = "/tmp/app"; }))
      "signAllMachO should chmod u-w after signing")

    (mkTest "codesign-signAllMachO-defines-function"
      (lib.hasInfix "_codesign_mach_o" (codesignLib.signAllMachO { path = "/tmp/app"; }))
      "signAllMachO should define _codesign_mach_o helper function")

    (mkTest "codesign-signAllMachO-with-entitlements"
      (lib.hasInfix "entFile" (codesignLib.signAllMachO { path = "/tmp/app"; entitlements = "/tmp/ent.plist"; }))
      "signAllMachO with entitlements should reference entFile")

    (mkTest "codesign-signAllMachO-no-entitlements-default"
      (!(lib.hasInfix "--entitlements" (codesignLib.signAllMachO { path = "/tmp/app"; })))
      "signAllMachO without entitlements should not include --entitlements")

    (mkTest "codesign-signAllMachO-uses-target-path"
      (lib.hasInfix "/tmp/app" (codesignLib.signAllMachO { path = "/tmp/app"; }))
      "signAllMachO should search the specified path")
  ];

  # ══════════════════════════════════════════════════════════════════════
  # sdk-helpers.nix tests (12 + 8 = 20)
  # ══════════════════════════════════════════════════════════════════════
  sdkTests = [
    # ── xcodeSDKPaths ──
    (mkTest "sdk-xcodeSDKPaths-is-list"
      (builtins.isList sdkHelpers.xcodeSDKPaths)
      "xcodeSDKPaths should be a list")

    (mkTest "sdk-xcodeSDKPaths-not-empty"
      (sdkHelpers.xcodeSDKPaths != [])
      "xcodeSDKPaths should not be empty")

    (mkTest "sdk-xcodeSDKPaths-has-two-entries"
      (builtins.length sdkHelpers.xcodeSDKPaths == 2)
      "xcodeSDKPaths should have exactly 2 entries (Xcode + CLT)")

    (mkTest "sdk-xcodeSDKPaths-contains-xcode-path"
      (builtins.any (p: lib.hasInfix "Xcode.app" p) sdkHelpers.xcodeSDKPaths)
      "xcodeSDKPaths should contain Xcode.app path")

    (mkTest "sdk-xcodeSDKPaths-contains-clt-path"
      (builtins.any (p: lib.hasInfix "CommandLineTools" p) sdkHelpers.xcodeSDKPaths)
      "xcodeSDKPaths should contain CommandLineTools path")

    (mkTest "sdk-xcodeSDKPaths-all-end-with-sdk"
      (builtins.all (p: lib.hasSuffix "MacOSX.sdk" p) sdkHelpers.xcodeSDKPaths)
      "xcodeSDKPaths should all end with MacOSX.sdk")

    # ── impureHostDeps ──
    (mkTest "sdk-impureHostDeps-is-list"
      (builtins.isList sdkHelpers.impureHostDeps)
      "impureHostDeps should be a list")

    (mkTest "sdk-impureHostDeps-has-five-entries"
      (builtins.length sdkHelpers.impureHostDeps == 5)
      "impureHostDeps should have exactly 5 entries")

    (mkTest "sdk-impureHostDeps-contains-usr-lib"
      (builtins.elem "/usr/lib" sdkHelpers.impureHostDeps)
      "impureHostDeps should include /usr/lib")

    (mkTest "sdk-impureHostDeps-contains-usr-bin"
      (builtins.elem "/usr/bin" sdkHelpers.impureHostDeps)
      "impureHostDeps should include /usr/bin")

    (mkTest "sdk-impureHostDeps-contains-frameworks"
      (builtins.elem "/System/Library/Frameworks" sdkHelpers.impureHostDeps)
      "impureHostDeps should include /System/Library/Frameworks")

    (mkTest "sdk-impureHostDeps-contains-library-developer"
      (builtins.elem "/Library/Developer" sdkHelpers.impureHostDeps)
      "impureHostDeps should include /Library/Developer")

    (mkTest "sdk-impureHostDeps-contains-xcode-app"
      (builtins.elem "/Applications/Xcode.app" sdkHelpers.impureHostDeps)
      "impureHostDeps should include /Applications/Xcode.app")

    # ── sdkrootDiscoveryScript ──
    (mkTest "sdk-sdkrootDiscoveryScript-is-string"
      (builtins.isString sdkHelpers.sdkrootDiscoveryScript)
      "sdkrootDiscoveryScript should be a string")

    (mkTest "sdk-sdkrootDiscoveryScript-uses-xcrun"
      (lib.hasInfix "xcrun" sdkHelpers.sdkrootDiscoveryScript)
      "sdkrootDiscoveryScript should try xcrun first")

    (mkTest "sdk-sdkrootDiscoveryScript-exports-SDKROOT"
      (lib.hasInfix "export SDKROOT" sdkHelpers.sdkrootDiscoveryScript)
      "sdkrootDiscoveryScript should export SDKROOT")

    (mkTest "sdk-sdkrootDiscoveryScript-fallback-xcode"
      (lib.hasInfix "Xcode.app" sdkHelpers.sdkrootDiscoveryScript)
      "sdkrootDiscoveryScript should fall back to Xcode.app path")

    (mkTest "sdk-sdkrootDiscoveryScript-fallback-clt"
      (lib.hasInfix "CommandLineTools" sdkHelpers.sdkrootDiscoveryScript)
      "sdkrootDiscoveryScript should fall back to CommandLineTools path")

    (mkTest "sdk-sdkrootDiscoveryScript-error-message"
      (lib.hasInfix "Could not find macOS SDK" sdkHelpers.sdkrootDiscoveryScript)
      "sdkrootDiscoveryScript should error if no SDK found")

    (mkTest "sdk-sdkrootDiscoveryScript-checks-existing"
      (lib.hasInfix "SDKROOT:-" sdkHelpers.sdkrootDiscoveryScript)
      "sdkrootDiscoveryScript should respect existing SDKROOT")

    # ── swiftUIAvailabilityCheck ──
    (mkTest "sdk-swiftUIAvailabilityCheck-is-string"
      (builtins.isString sdkHelpers.swiftUIAvailabilityCheck)
      "swiftUIAvailabilityCheck should be a string")

    (mkTest "sdk-swiftUIAvailabilityCheck-checks-framework"
      (lib.hasInfix "SwiftUI.framework" sdkHelpers.swiftUIAvailabilityCheck)
      "swiftUIAvailabilityCheck should check for SwiftUI.framework")

    (mkTest "sdk-swiftUIAvailabilityCheck-error-message"
      (lib.hasInfix "SwiftUI not found" sdkHelpers.swiftUIAvailabilityCheck)
      "swiftUIAvailabilityCheck should give meaningful error")

    (mkTest "sdk-swiftUIAvailabilityCheck-xcode-hint"
      (lib.hasInfix "Xcode" sdkHelpers.swiftUIAvailabilityCheck)
      "swiftUIAvailabilityCheck should hint about requiring Xcode")
  ];

  # ══════════════════════════════════════════════════════════════════════
  # sandbox.nix tests (6 + 12 = 18)
  # ══════════════════════════════════════════════════════════════════════
  sandboxTests = let
    impureDefault = sandbox.mkImpureDarwinAttrs {};
    impureSwiftUI = sandbox.mkImpureDarwinAttrs { needsSwiftUI = true; };
    impureXcode = sandbox.mkImpureDarwinAttrs { needsXcodebuild = true; };
    impureBoth = sandbox.mkImpureDarwinAttrs { needsSwiftUI = true; needsXcodebuild = true; };

    # Test mkPureSDKInputs with different pkgs mocks
    pureNewSDK = sandbox.mkPureSDKInputs mockPkgs;
    pureOldSDK = sandbox.mkPureSDKInputs mockPkgsOldSDK;
    pureMinimal = sandbox.mkPureSDKInputs mockPkgsMinimal;
  in [
    # ── mkImpureDarwinAttrs ──
    (mkTest "sandbox-impure-noChroot"
      (impureDefault.__noChroot == true)
      "mkImpureDarwinAttrs should set __noChroot = true")

    (mkTest "sandbox-impure-has-hostDeps"
      (builtins.isList impureDefault.impureHostDeps)
      "mkImpureDarwinAttrs should include impureHostDeps")

    (mkTest "sandbox-impure-hostDeps-matches-sdkHelpers"
      (impureDefault.impureHostDeps == sdkHelpers.impureHostDeps)
      "mkImpureDarwinAttrs hostDeps should match sdk-helpers impureHostDeps")

    (mkTest "sandbox-impure-has-preBuild"
      (builtins.isString impureDefault.preBuild)
      "mkImpureDarwinAttrs should set preBuild script")

    (mkTest "sandbox-impure-preBuild-has-sdkroot"
      (lib.hasInfix "SDKROOT" impureDefault.preBuild)
      "mkImpureDarwinAttrs preBuild should discover SDKROOT")

    (mkTest "sandbox-impure-preBuild-has-export"
      (lib.hasInfix "export SDKROOT" impureDefault.preBuild)
      "mkImpureDarwinAttrs preBuild should export SDKROOT")

    (mkTest "sandbox-impure-swiftui-checks-framework"
      (lib.hasInfix "SwiftUI.framework" impureSwiftUI.preBuild)
      "mkImpureDarwinAttrs with needsSwiftUI should check for SwiftUI.framework")

    (mkTest "sandbox-impure-default-no-swiftui-check"
      (!(lib.hasInfix "SwiftUI.framework" impureDefault.preBuild))
      "mkImpureDarwinAttrs without needsSwiftUI should not check for SwiftUI.framework")

    (mkTest "sandbox-impure-xcodebuild-still-has-sdkroot"
      (lib.hasInfix "SDKROOT" impureXcode.preBuild)
      "mkImpureDarwinAttrs with needsXcodebuild should still discover SDKROOT")

    (mkTest "sandbox-impure-xcodebuild-no-swiftui-check"
      (!(lib.hasInfix "SwiftUI.framework" impureXcode.preBuild))
      "mkImpureDarwinAttrs with only needsXcodebuild should not check SwiftUI")

    (mkTest "sandbox-impure-both-has-swiftui-check"
      (lib.hasInfix "SwiftUI.framework" impureBoth.preBuild)
      "mkImpureDarwinAttrs with both needsSwiftUI+needsXcodebuild should check SwiftUI")

    (mkTest "sandbox-impure-both-has-sdkroot"
      (lib.hasInfix "export SDKROOT" impureBoth.preBuild)
      "mkImpureDarwinAttrs with both should still discover SDKROOT")

    # ── mkPureSDKInputs ──
    (mkTest "sandbox-pure-new-sdk-has-apple-sdk"
      (builtins.elem "/nix/store/mock-apple-sdk" pureNewSDK)
      "mkPureSDKInputs with new nixpkgs should include apple-sdk")

    (mkTest "sandbox-pure-new-sdk-length"
      (builtins.length pureNewSDK == 1)
      "mkPureSDKInputs with new nixpkgs should have exactly 1 item")

    (mkTest "sandbox-pure-old-sdk-has-frameworks"
      (builtins.length pureOldSDK == 4)
      "mkPureSDKInputs with old nixpkgs should include 4 frameworks")

    (mkTest "sandbox-pure-old-sdk-has-foundation"
      (builtins.elem "mock-Foundation" pureOldSDK)
      "mkPureSDKInputs with old nixpkgs should include Foundation")

    (mkTest "sandbox-pure-old-sdk-has-appkit"
      (builtins.elem "mock-AppKit" pureOldSDK)
      "mkPureSDKInputs with old nixpkgs should include AppKit")

    (mkTest "sandbox-pure-minimal-empty"
      (pureMinimal == [])
      "mkPureSDKInputs with minimal pkgs should return empty list")
  ];

  # ══════════════════════════════════════════════════════════════════════
  # overlay.nix tests (2 + 2 = 4)
  # ══════════════════════════════════════════════════════════════════════
  overlayTests = [
    (mkTest "overlay-mkSwiftOverlay-is-function"
      (builtins.isFunction overlayLib.mkSwiftOverlay)
      "mkSwiftOverlay should be a function")

    (mkTest "overlay-mkSwiftOverlay-returns-function"
      (builtins.isFunction (overlayLib.mkSwiftOverlay {}))
      "mkSwiftOverlay {} should return an overlay function")

    (mkTest "overlay-single-export"
      (builtins.attrNames overlayLib == [ "mkSwiftOverlay" ])
      "overlay.nix should export only mkSwiftOverlay")

    (mkTest "overlay-mkSwiftOverlay-takes-empty-attrset"
      (builtins.isFunction (overlayLib.mkSwiftOverlay {}))
      "mkSwiftOverlay should accept {} as argument")
  ];

  # ══════════════════════════════════════════════════════════════════════
  # lib export structure tests (14 + 6 = 20)
  # ══════════════════════════════════════════════════════════════════════
  libStructureTests = [
    # ── codesign.nix exports ──
    (mkTest "lib-codesign-has-adHocSign"
      (codesignLib ? adHocSign)
      "codesign.nix should export adHocSign")

    (mkTest "lib-codesign-has-mkEntitlements"
      (codesignLib ? mkEntitlements)
      "codesign.nix should export mkEntitlements")

    (mkTest "lib-codesign-has-signAllMachO"
      (codesignLib ? signAllMachO)
      "codesign.nix should export signAllMachO")

    (mkTest "lib-codesign-exact-exports"
      (builtins.sort builtins.lessThan (builtins.attrNames codesignLib)
        == [ "adHocSign" "mkEntitlements" "signAllMachO" ])
      "codesign.nix should export exactly {adHocSign, mkEntitlements, signAllMachO}")

    # ── sdk-helpers.nix exports ──
    (mkTest "lib-sdk-has-xcodeSDKPaths"
      (sdkHelpers ? xcodeSDKPaths)
      "sdk-helpers.nix should export xcodeSDKPaths")

    (mkTest "lib-sdk-has-impureHostDeps"
      (sdkHelpers ? impureHostDeps)
      "sdk-helpers.nix should export impureHostDeps")

    (mkTest "lib-sdk-has-sdkrootDiscoveryScript"
      (sdkHelpers ? sdkrootDiscoveryScript)
      "sdk-helpers.nix should export sdkrootDiscoveryScript")

    (mkTest "lib-sdk-has-swiftUIAvailabilityCheck"
      (sdkHelpers ? swiftUIAvailabilityCheck)
      "sdk-helpers.nix should export swiftUIAvailabilityCheck")

    (mkTest "lib-sdk-exact-exports"
      (builtins.sort builtins.lessThan (builtins.attrNames sdkHelpers)
        == [ "impureHostDeps" "sdkrootDiscoveryScript" "swiftUIAvailabilityCheck" "xcodeSDKPaths" ])
      "sdk-helpers.nix should export exactly 4 attributes")

    # ── sandbox.nix exports ──
    (mkTest "lib-sandbox-has-mkImpureDarwinAttrs"
      (sandbox ? mkImpureDarwinAttrs)
      "sandbox.nix should export mkImpureDarwinAttrs")

    (mkTest "lib-sandbox-has-mkPureSDKInputs"
      (sandbox ? mkPureSDKInputs)
      "sandbox.nix should export mkPureSDKInputs")

    (mkTest "lib-sandbox-exact-exports"
      (builtins.sort builtins.lessThan (builtins.attrNames sandbox)
        == [ "mkImpureDarwinAttrs" "mkPureSDKInputs" ])
      "sandbox.nix should export exactly {mkImpureDarwinAttrs, mkPureSDKInputs}")

    # ── build helper module exports ──
    (mkTest "lib-swift-package-has-mkSwiftPackage"
      (swiftPkgLib ? mkSwiftPackage)
      "swift-package.nix should export mkSwiftPackage")

    (mkTest "lib-swift-app-has-mkSwiftApp"
      (swiftAppLib ? mkSwiftApp)
      "swift-app.nix should export mkSwiftApp")

    (mkTest "lib-zig-swift-has-mkZigSwiftApp"
      (zigSwiftLib ? mkZigSwiftApp)
      "zig-swift-app.nix should export mkZigSwiftApp")

    (mkTest "lib-xcode-project-has-mkXcodeProject"
      (xcodeProjLib ? mkXcodeProject)
      "xcode-project.nix should export mkXcodeProject")

    (mkTest "lib-overlay-has-mkSwiftOverlay"
      (overlayLib ? mkSwiftOverlay)
      "overlay.nix should export mkSwiftOverlay")

    # ── type checks ──
    (mkTest "lib-mkSwiftPackage-is-function"
      (builtins.isFunction swiftPkgLib.mkSwiftPackage)
      "mkSwiftPackage should be a function")

    (mkTest "lib-mkSwiftApp-is-function"
      (builtins.isFunction swiftAppLib.mkSwiftApp)
      "mkSwiftApp should be a function")

    (mkTest "lib-mkZigSwiftApp-is-function"
      (builtins.isFunction zigSwiftLib.mkZigSwiftApp)
      "mkZigSwiftApp should be a function")

    (mkTest "lib-mkXcodeProject-is-function"
      (builtins.isFunction xcodeProjLib.mkXcodeProject)
      "mkXcodeProject should be a function")
  ];

  # ══════════════════════════════════════════════════════════════════════
  # Build helper factory tests — mkSwiftPackage (8)
  # ══════════════════════════════════════════════════════════════════════
  swiftPackageTests = let
    mkPkg = swiftPkgLib.mkSwiftPackage mockPkgs;

    defaultPkg = mkPkg {
      pname = "test-tool";
      version = "1.0.0";
      src = "/mock/src";
    };

    swiftUIPkg = mkPkg {
      pname = "swiftui-tool";
      version = "2.0.0";
      src = "/mock/src";
      needsSwiftUI = true;
    };

    customFlagsPkg = mkPkg {
      pname = "custom-tool";
      version = "3.0.0";
      src = "/mock/src";
      swiftFlags = [ "-Xswiftc" "-O" ];
      buildConfiguration = "debug";
      products = [ "tool-a" "tool-b" ];
    };
  in [
    (mkTest "swiftpkg-returns-attrset"
      (builtins.isAttrs defaultPkg)
      "mkSwiftPackage should return an attrset (derivation attrs)")

    (mkTest "swiftpkg-has-pname"
      (defaultPkg.pname == "test-tool")
      "mkSwiftPackage result should have correct pname")

    (mkTest "swiftpkg-has-version"
      (defaultPkg.version == "1.0.0")
      "mkSwiftPackage result should have correct version")

    (mkTest "swiftpkg-buildPhase-has-swift-build"
      (lib.hasInfix "swift build" defaultPkg.buildPhase)
      "mkSwiftPackage buildPhase should invoke swift build")

    (mkTest "swiftpkg-buildPhase-release-config"
      (lib.hasInfix "-c release" defaultPkg.buildPhase)
      "mkSwiftPackage buildPhase should use release configuration by default")

    (mkTest "swiftpkg-buildPhase-disable-sandbox"
      (lib.hasInfix "--disable-sandbox" defaultPkg.buildPhase)
      "mkSwiftPackage buildPhase should include --disable-sandbox")

    (mkTest "swiftpkg-installPhase-has-install"
      (lib.hasInfix "install -Dm755" defaultPkg.installPhase)
      "mkSwiftPackage installPhase should install binaries")

    (mkTest "swiftpkg-installPhase-product-name"
      (lib.hasInfix "test-tool" defaultPkg.installPhase)
      "mkSwiftPackage installPhase should reference product name")

    (mkTest "swiftpkg-meta-darwin-only"
      (defaultPkg.meta.platforms == [ "x86_64-darwin" "aarch64-darwin" ])
      "mkSwiftPackage meta should be Darwin-only")

    (mkTest "swiftpkg-nativeBuildInputs-has-swift"
      (builtins.elem "/nix/store/mock-swift-toolchain" defaultPkg.nativeBuildInputs)
      "mkSwiftPackage should include swiftToolchain in nativeBuildInputs")

    (mkTest "swiftpkg-pure-no-noChroot"
      (!(defaultPkg ? __noChroot))
      "mkSwiftPackage pure build should not set __noChroot")

    (mkTest "swiftpkg-swiftui-has-noChroot"
      (swiftUIPkg.__noChroot == true)
      "mkSwiftPackage with needsSwiftUI should set __noChroot")

    (mkTest "swiftpkg-swiftui-buildPhase-has-sdkroot"
      (lib.hasInfix "SDKROOT" swiftUIPkg.buildPhase)
      "mkSwiftPackage with needsSwiftUI should discover SDKROOT in buildPhase")

    (mkTest "swiftpkg-custom-flags"
      (lib.hasInfix "-Xswiftc" customFlagsPkg.buildPhase
        && lib.hasInfix "-O" customFlagsPkg.buildPhase)
      "mkSwiftPackage should pass custom swift flags")

    (mkTest "swiftpkg-custom-config"
      (lib.hasInfix "-c debug" customFlagsPkg.buildPhase)
      "mkSwiftPackage should use custom build configuration")

    (mkTest "swiftpkg-multiple-products"
      (lib.hasInfix "tool-a" customFlagsPkg.installPhase
        && lib.hasInfix "tool-b" customFlagsPkg.installPhase)
      "mkSwiftPackage should install multiple products")
  ];

  # ══════════════════════════════════════════════════════════════════════
  # Build helper factory tests — mkSwiftApp (10)
  # ══════════════════════════════════════════════════════════════════════
  swiftAppTests = let
    mkApp = swiftAppLib.mkSwiftApp mockPkgs;

    defaultApp = mkApp {
      pname = "TestApp";
      version = "1.0.0";
      src = "/mock/src";
      bundleIdentifier = "io.pleme.testapp";
    };

    noCodesignApp = mkApp {
      pname = "UnsignedApp";
      version = "1.0.0";
      src = "/mock/src";
      bundleIdentifier = "io.pleme.unsigned";
      codesign = false;
    };

    frameworkApp = mkApp {
      pname = "FrameworkApp";
      version = "1.0.0";
      src = "/mock/src";
      bundleIdentifier = "io.pleme.framework";
      frameworks = [ "Metal" "CoreGraphics" ];
    };
  in [
    (mkTest "swiftapp-returns-attrset"
      (builtins.isAttrs defaultApp)
      "mkSwiftApp should return an attrset")

    (mkTest "swiftapp-has-pname"
      (defaultApp.pname == "TestApp")
      "mkSwiftApp result should have correct pname")

    (mkTest "swiftapp-impure-by-default"
      (defaultApp.__noChroot == true)
      "mkSwiftApp should be impure by default (needsSwiftUI=true)")

    (mkTest "swiftapp-buildPhase-swift-build"
      (lib.hasInfix "swift build" defaultApp.buildPhase)
      "mkSwiftApp buildPhase should invoke swift build")

    (mkTest "swiftapp-buildPhase-sdkroot"
      (lib.hasInfix "SDKROOT" defaultApp.buildPhase)
      "mkSwiftApp buildPhase should discover SDKROOT")

    (mkTest "swiftapp-buildPhase-swiftui-check"
      (lib.hasInfix "SwiftUI.framework" defaultApp.buildPhase)
      "mkSwiftApp buildPhase should check SwiftUI availability by default")

    (mkTest "swiftapp-installPhase-app-bundle"
      (lib.hasInfix "Applications/TestApp.app" defaultApp.installPhase)
      "mkSwiftApp installPhase should create .app bundle")

    (mkTest "swiftapp-installPhase-contents-macos"
      (lib.hasInfix "Contents/MacOS" defaultApp.installPhase)
      "mkSwiftApp installPhase should create Contents/MacOS directory")

    (mkTest "swiftapp-installPhase-contents-resources"
      (lib.hasInfix "Contents/Resources" defaultApp.installPhase)
      "mkSwiftApp installPhase should create Contents/Resources directory")

    (mkTest "swiftapp-installPhase-info-plist"
      (lib.hasInfix "Info.plist" defaultApp.installPhase)
      "mkSwiftApp installPhase should install Info.plist")

    (mkTest "swiftapp-postFixup-codesign"
      (lib.hasInfix "codesign" defaultApp.postFixup)
      "mkSwiftApp postFixup should codesign by default")

    (mkTest "swiftapp-postFixup-signAllMachO"
      (lib.hasInfix "_codesign_mach_o" defaultApp.postFixup)
      "mkSwiftApp postFixup should use signAllMachO pattern")

    (mkTest "swiftapp-no-codesign-empty-postFixup"
      (noCodesignApp.postFixup == "")
      "mkSwiftApp with codesign=false should have empty postFixup")

    (mkTest "swiftapp-framework-flags"
      (lib.hasInfix "Metal" frameworkApp.buildPhase
        && lib.hasInfix "CoreGraphics" frameworkApp.buildPhase)
      "mkSwiftApp should pass framework linker flags")

    (mkTest "swiftapp-framework-xlinker"
      (lib.hasInfix "-Xlinker -framework" frameworkApp.buildPhase)
      "mkSwiftApp should use -Xlinker -framework pattern")

    (mkTest "swiftapp-meta-darwin-only"
      (defaultApp.meta.platforms == [ "x86_64-darwin" "aarch64-darwin" ])
      "mkSwiftApp meta should be Darwin-only")
  ];

  # ══════════════════════════════════════════════════════════════════════
  # Build helper factory tests — mkZigSwiftApp (10)
  # ══════════════════════════════════════════════════════════════════════
  zigSwiftAppTests = let
    mkZigApp = zigSwiftLib.mkZigSwiftApp mockPkgs;

    defaultZigApp = mkZigApp {
      pname = "Ghostty";
      version = "1.0.0";
      src = "/mock/src";
    };

    customZigApp = mkZigApp {
      pname = "CustomApp";
      version = "2.0.0";
      src = "/mock/src";
      bundleIdentifier = "com.example.custom";
      zigBuildFlags = [ "-Doptimize=ReleaseSafe" "-Dpie=true" ];
      codesign = false;
    };

    overrideApp = mkZigApp {
      pname = "OverrideApp";
      version = "1.0.0";
      src = "/mock/src";
      buildPhaseOverride = "echo custom build";
      installPhaseOverride = "echo custom install";
    };
  in [
    (mkTest "zigswift-returns-attrset"
      (builtins.isAttrs defaultZigApp)
      "mkZigSwiftApp should return an attrset")

    (mkTest "zigswift-has-pname"
      (defaultZigApp.pname == "Ghostty")
      "mkZigSwiftApp result should have correct pname")

    (mkTest "zigswift-impure"
      (defaultZigApp.__noChroot == true)
      "mkZigSwiftApp should be impure (needs system SDK)")

    (mkTest "zigswift-buildPhase-zig-build"
      (lib.hasInfix "zig build" defaultZigApp.buildPhase)
      "mkZigSwiftApp buildPhase should invoke zig build")

    (mkTest "zigswift-buildPhase-sdkroot"
      (lib.hasInfix "SDKROOT" defaultZigApp.buildPhase)
      "mkZigSwiftApp buildPhase should discover SDKROOT")

    (mkTest "zigswift-buildPhase-release-fast"
      (lib.hasInfix "ReleaseFast" defaultZigApp.buildPhase)
      "mkZigSwiftApp buildPhase should default to ReleaseFast")

    (mkTest "zigswift-nativeBuildInputs-has-zig"
      (builtins.elem "/nix/store/mock-zig-toolchain" defaultZigApp.nativeBuildInputs)
      "mkZigSwiftApp should include zigToolchain in nativeBuildInputs")

    (mkTest "zigswift-nativeBuildInputs-has-swift"
      (builtins.elem "/nix/store/mock-swift-toolchain" defaultZigApp.nativeBuildInputs)
      "mkZigSwiftApp should include swiftToolchain in nativeBuildInputs")

    (mkTest "zigswift-postFixup-codesign"
      (lib.hasInfix "codesign" defaultZigApp.postFixup)
      "mkZigSwiftApp postFixup should codesign by default")

    (mkTest "zigswift-postFixup-jit-entitlement"
      (lib.hasInfix "allow-jit" defaultZigApp.postFixup)
      "mkZigSwiftApp should include JIT entitlement by default")

    (mkTest "zigswift-installPhase-applications"
      (lib.hasInfix "Applications" defaultZigApp.installPhase)
      "mkZigSwiftApp installPhase should install to Applications")

    (mkTest "zigswift-installPhase-zig-out"
      (lib.hasInfix "zig-out" defaultZigApp.installPhase)
      "mkZigSwiftApp installPhase should look for zig-out directory")

    (mkTest "zigswift-installPhase-cli-bin"
      (lib.hasInfix "zig-out/bin" defaultZigApp.installPhase)
      "mkZigSwiftApp installPhase should install CLI binary if present")

    (mkTest "zigswift-postFixup-signs-app-bundles"
      (lib.hasInfix "Applications/*.app" defaultZigApp.postFixup)
      "mkZigSwiftApp postFixup should sign .app bundles")

    (mkTest "zigswift-custom-flags"
      (lib.hasInfix "-Doptimize=ReleaseSafe" customZigApp.buildPhase
        && lib.hasInfix "-Dpie=true" customZigApp.buildPhase)
      "mkZigSwiftApp should pass custom zig build flags")

    (mkTest "zigswift-no-codesign"
      (customZigApp.postFixup == "")
      "mkZigSwiftApp with codesign=false should have empty postFixup")

    (mkTest "zigswift-build-override"
      (overrideApp.buildPhase == "echo custom build")
      "mkZigSwiftApp with buildPhaseOverride should use it")

    (mkTest "zigswift-install-override"
      (overrideApp.installPhase == "echo custom install")
      "mkZigSwiftApp with installPhaseOverride should use it")

    (mkTest "zigswift-meta-darwin-only"
      (defaultZigApp.meta.platforms == [ "x86_64-darwin" "aarch64-darwin" ])
      "mkZigSwiftApp meta should be Darwin-only")
  ];

  # ══════════════════════════════════════════════════════════════════════
  # Build helper factory tests — mkXcodeProject (10)
  # ══════════════════════════════════════════════════════════════════════
  xcodeProjectTests = let
    mkXcode = xcodeProjLib.mkXcodeProject mockPkgs;

    defaultXcode = mkXcode {
      pname = "MyApp";
      version = "1.0.0";
      src = "/mock/src";
      scheme = "MyApp";
    };

    workspaceXcode = mkXcode {
      pname = "WorkspaceApp";
      version = "1.0.0";
      src = "/mock/src";
      scheme = "WorkspaceApp";
      workspace = "MyApp.xcworkspace";
    };

    projectXcode = mkXcode {
      pname = "ProjectApp";
      version = "1.0.0";
      src = "/mock/src";
      scheme = "ProjectApp";
      project = "ProjectApp.xcodeproj";
      configuration = "Debug";
    };

    noCodesignXcode = mkXcode {
      pname = "UnsignedApp";
      version = "1.0.0";
      src = "/mock/src";
      scheme = "UnsignedApp";
      codesign = false;
    };
  in [
    (mkTest "xcode-returns-attrset"
      (builtins.isAttrs defaultXcode)
      "mkXcodeProject should return an attrset")

    (mkTest "xcode-has-pname"
      (defaultXcode.pname == "MyApp")
      "mkXcodeProject result should have correct pname")

    (mkTest "xcode-impure"
      (defaultXcode.__noChroot == true)
      "mkXcodeProject should be impure (needs system xcodebuild)")

    (mkTest "xcode-buildPhase-xcodebuild"
      (lib.hasInfix "/usr/bin/xcodebuild" defaultXcode.buildPhase)
      "mkXcodeProject buildPhase should invoke /usr/bin/xcodebuild")

    (mkTest "xcode-buildPhase-scheme"
      (lib.hasInfix "MyApp" defaultXcode.buildPhase)
      "mkXcodeProject buildPhase should include scheme name")

    (mkTest "xcode-buildPhase-release-config"
      (lib.hasInfix "Release" defaultXcode.buildPhase)
      "mkXcodeProject buildPhase should default to Release configuration")

    (mkTest "xcode-buildPhase-no-sign"
      (lib.hasInfix "CODE_SIGNING_REQUIRED=NO" defaultXcode.buildPhase)
      "mkXcodeProject should disable Xcode code signing")

    (mkTest "xcode-buildPhase-sdkroot"
      (lib.hasInfix "SDKROOT" defaultXcode.buildPhase)
      "mkXcodeProject buildPhase should discover SDKROOT")

    (mkTest "xcode-installPhase-find-app"
      (lib.hasInfix "find" defaultXcode.installPhase)
      "mkXcodeProject installPhase should find .app bundle")

    (mkTest "xcode-installPhase-applications"
      (lib.hasInfix "Applications" defaultXcode.installPhase)
      "mkXcodeProject installPhase should copy to Applications")

    (mkTest "xcode-workspace-flag"
      (lib.hasInfix "-workspace" workspaceXcode.buildPhase)
      "mkXcodeProject with workspace should include -workspace flag")

    (mkTest "xcode-workspace-name"
      (lib.hasInfix "MyApp.xcworkspace" workspaceXcode.buildPhase)
      "mkXcodeProject with workspace should reference workspace file")

    (mkTest "xcode-project-flag"
      (lib.hasInfix "-project" projectXcode.buildPhase)
      "mkXcodeProject with project should include -project flag")

    (mkTest "xcode-project-name"
      (lib.hasInfix "ProjectApp.xcodeproj" projectXcode.buildPhase)
      "mkXcodeProject with project should reference project file")

    (mkTest "xcode-debug-config"
      (lib.hasInfix "Debug" projectXcode.buildPhase)
      "mkXcodeProject should use custom configuration")

    (mkTest "xcode-postFixup-codesign"
      (lib.hasInfix "codesign" defaultXcode.postFixup)
      "mkXcodeProject postFixup should codesign by default")

    (mkTest "xcode-no-codesign-postFixup"
      (noCodesignXcode.postFixup == "")
      "mkXcodeProject with codesign=false should have empty postFixup")

    (mkTest "xcode-meta-darwin-only"
      (defaultXcode.meta.platforms == [ "x86_64-darwin" "aarch64-darwin" ])
      "mkXcodeProject meta should be Darwin-only")
  ];

  # ══════════════════════════════════════════════════════════════════════
  # unified API (lib/default.nix) tests (10 + 8 = 18)
  # ══════════════════════════════════════════════════════════════════════
  unifiedApiTests = [
    # ── Attribute existence ──
    (mkTest "unified-has-mkSwiftOverlay"
      (macosLib ? mkSwiftOverlay)
      "lib/default.nix should export mkSwiftOverlay")

    (mkTest "unified-has-sdkHelpers"
      (macosLib ? sdkHelpers)
      "lib/default.nix should export sdkHelpers")

    (mkTest "unified-has-sandbox"
      (macosLib ? sandbox)
      "lib/default.nix should export sandbox")

    (mkTest "unified-has-codesign"
      (macosLib ? codesign)
      "lib/default.nix should export codesign")

    (mkTest "unified-has-mkSwiftPackage"
      (macosLib ? mkSwiftPackage)
      "lib/default.nix should export mkSwiftPackage")

    (mkTest "unified-has-mkSwiftApp"
      (macosLib ? mkSwiftApp)
      "lib/default.nix should export mkSwiftApp")

    (mkTest "unified-has-mkZigSwiftApp"
      (macosLib ? mkZigSwiftApp)
      "lib/default.nix should export mkZigSwiftApp")

    (mkTest "unified-has-mkXcodeProject"
      (macosLib ? mkXcodeProject)
      "lib/default.nix should export mkXcodeProject")

    # ── Type checks ──
    (mkTest "unified-mkSwiftOverlay-is-function"
      (builtins.isFunction macosLib.mkSwiftOverlay)
      "unified mkSwiftOverlay should be a function")

    (mkTest "unified-mkSwiftPackage-is-function"
      (builtins.isFunction macosLib.mkSwiftPackage)
      "unified mkSwiftPackage should be a function")

    (mkTest "unified-mkSwiftApp-is-function"
      (builtins.isFunction macosLib.mkSwiftApp)
      "unified mkSwiftApp should be a function")

    (mkTest "unified-mkZigSwiftApp-is-function"
      (builtins.isFunction macosLib.mkZigSwiftApp)
      "unified mkZigSwiftApp should be a function")

    (mkTest "unified-mkXcodeProject-is-function"
      (builtins.isFunction macosLib.mkXcodeProject)
      "unified mkXcodeProject should be a function")

    (mkTest "unified-sdkHelpers-is-attrset"
      (builtins.isAttrs macosLib.sdkHelpers)
      "unified sdkHelpers should be an attrset")

    (mkTest "unified-sandbox-is-attrset"
      (builtins.isAttrs macosLib.sandbox)
      "unified sandbox should be an attrset")

    (mkTest "unified-codesign-is-attrset"
      (builtins.isAttrs macosLib.codesign)
      "unified codesign should be an attrset")

    # ── Consistency with direct imports ──
    (mkTest "unified-codesign-matches-direct"
      (macosLib.codesign.adHocSign { path = "/test"; } == codesignLib.adHocSign { path = "/test"; })
      "unified codesign should match direct import")

    (mkTest "unified-sdkHelpers-matches-direct"
      (macosLib.sdkHelpers.xcodeSDKPaths == sdkHelpers.xcodeSDKPaths)
      "unified sdkHelpers should match direct import")

    (mkTest "unified-sandbox-matches-direct"
      (macosLib.sandbox.mkImpureDarwinAttrs {} == sandbox.mkImpureDarwinAttrs {})
      "unified sandbox should match direct import")

    (mkTest "unified-codesign-mkEntitlements-matches"
      (macosLib.codesign.mkEntitlements { allowJit = true; }
        == codesignLib.mkEntitlements { allowJit = true; })
      "unified codesign.mkEntitlements should match direct import")

    (mkTest "unified-codesign-signAllMachO-matches"
      (macosLib.codesign.signAllMachO { path = "/test"; }
        == codesignLib.signAllMachO { path = "/test"; })
      "unified codesign.signAllMachO should match direct import")

    # ── Exact attribute count ──
    (mkTest "unified-exact-exports"
      (builtins.sort builtins.lessThan (builtins.attrNames macosLib) == [
        "codesign" "mkSwiftApp" "mkSwiftOverlay" "mkSwiftPackage"
        "mkXcodeProject" "mkZigSwiftApp" "sandbox" "sdkHelpers"
      ])
      "lib/default.nix should export exactly 8 attributes")
  ];

  # ══════════════════════════════════════════════════════════════════════
  # module evaluation tests (8 + 6 = 14)
  # ══════════════════════════════════════════════════════════════════════
  moduleTests = let
    # Helper to evaluate the module with a given pkgs mock
    evalModule = { isDarwin ? false, enableMacos ? false, enableSwift ? true }:
      lib.evalModules {
        modules = [
          (import ../module)
          ({ ... }: {
            config._module.args.pkgs = {
              stdenv.hostPlatform.isDarwin = isDarwin;
              swiftToolchain = "mock-swift-toolchain";
              swift = "mock-swift";
            };
            options.home.packages = lib.mkOption {
              type = lib.types.listOf lib.types.unspecified;
              default = [];
            };
          })
          ({ ... }: {
            blackmatter.components.macos.enable = enableMacos;
            blackmatter.components.macos.swift.enable = enableSwift;
          })
        ];
      };

    # Evaluate with only pkgs.swift (no swiftToolchain)
    evalModuleFallback =
      lib.evalModules {
        modules = [
          (import ../module)
          ({ ... }: {
            config._module.args.pkgs = {
              stdenv.hostPlatform.isDarwin = true;
              swift = "mock-swift-fallback";
            };
            options.home.packages = lib.mkOption {
              type = lib.types.listOf lib.types.unspecified;
              default = [];
            };
          })
          ({ ... }: {
            blackmatter.components.macos.enable = true;
            blackmatter.components.macos.swift.enable = true;
          })
        ];
      };

    # Default (disabled)
    defaultResult = evalModule {};
    # Enabled on Darwin
    darwinEnabled = evalModule { isDarwin = true; enableMacos = true; };
    # Enabled on Darwin with swift disabled
    darwinNoSwift = evalModule { isDarwin = true; enableMacos = true; enableSwift = false; };
    # Enabled on Linux (should no-op)
    linuxEnabled = evalModule { isDarwin = false; enableMacos = true; };
    # Disabled but on Darwin
    darwinDisabled = evalModule { isDarwin = true; enableMacos = false; };
  in [
    # ── Option structure ──
    (mkTest "module-has-macos-option"
      (defaultResult.options ? blackmatter)
      "module should define blackmatter option namespace")

    (mkTest "module-has-components-option"
      (defaultResult.options.blackmatter ? components)
      "module should define blackmatter.components")

    (mkTest "module-has-macos-enable"
      (defaultResult.options.blackmatter.components.macos ? enable)
      "module should define blackmatter.components.macos.enable")

    (mkTest "module-has-swift-option"
      (defaultResult.options.blackmatter.components.macos ? swift)
      "module should define blackmatter.components.macos.swift")

    (mkTest "module-has-swift-enable"
      (defaultResult.options.blackmatter.components.macos.swift ? enable)
      "module should define blackmatter.components.macos.swift.enable")

    # ── Default values ──
    (mkTest "module-macos-enable-default-false"
      (defaultResult.config.blackmatter.components.macos.enable == false)
      "blackmatter.components.macos.enable should default to false")

    (mkTest "module-swift-enable-default-true"
      (defaultResult.config.blackmatter.components.macos.swift.enable == true)
      "blackmatter.components.macos.swift.enable should default to true")

    # ── Package behavior ──
    (mkTest "module-disabled-no-packages"
      (defaultResult.config.home.packages == [])
      "disabled module should add no packages")

    (mkTest "module-darwin-enabled-has-packages"
      (darwinEnabled.config.home.packages != [])
      "enabled on Darwin should add packages")

    (mkTest "module-darwin-enabled-one-package"
      (builtins.length darwinEnabled.config.home.packages == 1)
      "enabled on Darwin should add exactly 1 package (swiftToolchain)")

    (mkTest "module-darwin-enabled-is-swiftToolchain"
      (builtins.head darwinEnabled.config.home.packages == "mock-swift-toolchain")
      "enabled on Darwin should add swiftToolchain specifically")

    (mkTest "module-darwin-no-swift-no-packages"
      (darwinNoSwift.config.home.packages == [])
      "enabled on Darwin with swift.enable=false should add no packages")

    (mkTest "module-linux-enabled-no-packages"
      (linuxEnabled.config.home.packages == [])
      "enabled on Linux should add no packages (Darwin-only)")

    (mkTest "module-darwin-disabled-no-packages"
      (darwinDisabled.config.home.packages == [])
      "disabled on Darwin should add no packages")

    (mkTest "module-fallback-to-swift"
      (builtins.head evalModuleFallback.config.home.packages == "mock-swift-fallback")
      "module should fall back to pkgs.swift if swiftToolchain is missing")
  ];

in
runTests (
  codesignTests
  ++ sdkTests
  ++ sandboxTests
  ++ overlayTests
  ++ libStructureTests
  ++ swiftPackageTests
  ++ swiftAppTests
  ++ zigSwiftAppTests
  ++ xcodeProjectTests
  ++ unifiedApiTests
  ++ moduleTests
)
