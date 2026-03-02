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
    inherit lib;
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
    installShellFiles = "/nix/store/mock-installShellFiles";
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

    # ── New exports ──
    (mkTest "unified-has-mkSwiftCompletionAttrs"
      (macosLib ? mkSwiftCompletionAttrs)
      "lib/default.nix should export mkSwiftCompletionAttrs")

    (mkTest "unified-mkSwiftCompletionAttrs-is-function"
      (builtins.isFunction macosLib.mkSwiftCompletionAttrs)
      "unified mkSwiftCompletionAttrs should be a function")

    (mkTest "unified-has-swiftToolRelease"
      (macosLib ? swiftToolRelease)
      "lib/default.nix should export swiftToolRelease")

    (mkTest "unified-swiftToolRelease-is-path"
      (builtins.isPath macosLib.swiftToolRelease)
      "unified swiftToolRelease should be a path")

    (mkTest "unified-mkSwiftCompletionAttrs-matches-direct"
      (let
        directLib = import ../lib/completions.nix;
        directResult = directLib.mkSwiftCompletionAttrs mockPkgs { pname = "test"; };
        unifiedResult = macosLib.mkSwiftCompletionAttrs mockPkgs { pname = "test"; };
      in directResult == unifiedResult)
      "unified mkSwiftCompletionAttrs should match direct import")

    # ── Exact attribute count ──
    (mkTest "unified-exact-exports"
      (builtins.sort builtins.lessThan (builtins.attrNames macosLib) == [
        "codesign" "mkSwiftApp" "mkSwiftCompletionAttrs" "mkSwiftOverlay"
        "mkSwiftPackage" "mkXcodeProject" "mkZigSwiftApp" "sandbox"
        "sdkHelpers" "swiftToolRelease"
      ])
      "lib/default.nix should export exactly 10 attributes")
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

  # ══════════════════════════════════════════════════════════════════════
  # completions.nix tests (18)
  # ══════════════════════════════════════════════════════════════════════
  completionTests = let
    completionsLib = import ../lib/completions.nix;
    mkCompletion = completionsLib.mkSwiftCompletionAttrs mockPkgs;

    nullResult = mkCompletion { pname = "test-tool"; completions = null; };
    disabledResult = mkCompletion { pname = "test-tool"; completions = { install = false; }; };
    enabledResult = mkCompletion { pname = "test-tool"; completions = { install = true; }; };
    customCmdResult = mkCompletion { pname = "test-tool"; completions = { install = true; command = "custom-cmd"; }; };
    defaultCmdResult = mkCompletion { pname = "my-tool"; completions = { install = true; }; };
  in [
    # null completions
    (mkTest "completion-null-empty-nativeBuildInputs"
      (nullResult.nativeBuildInputs == [])
      "null completions should produce empty nativeBuildInputs")

    (mkTest "completion-null-empty-postInstallScript"
      (nullResult.postInstallScript == "")
      "null completions should produce empty postInstallScript")

    # disabled completions
    (mkTest "completion-disabled-empty-nativeBuildInputs"
      (disabledResult.nativeBuildInputs == [])
      "install=false should produce empty nativeBuildInputs")

    (mkTest "completion-disabled-empty-postInstallScript"
      (disabledResult.postInstallScript == "")
      "install=false should produce empty postInstallScript")

    # enabled completions
    (mkTest "completion-enabled-has-installShellFiles"
      (builtins.elem "/nix/store/mock-installShellFiles" enabledResult.nativeBuildInputs)
      "install=true should include installShellFiles in nativeBuildInputs")

    (mkTest "completion-enabled-nativeBuildInputs-length"
      (builtins.length enabledResult.nativeBuildInputs == 1)
      "install=true should have exactly 1 nativeBuildInput")

    (mkTest "completion-enabled-postInstall-is-string"
      (builtins.isString enabledResult.postInstallScript)
      "install=true should produce string postInstallScript")

    (mkTest "completion-enabled-has-generate-completion-script"
      (lib.hasInfix "--generate-completion-script" enabledResult.postInstallScript)
      "install=true should use --generate-completion-script")

    (mkTest "completion-enabled-has-bash"
      (lib.hasInfix "bash" enabledResult.postInstallScript)
      "install=true should generate bash completions")

    (mkTest "completion-enabled-has-zsh"
      (lib.hasInfix "zsh" enabledResult.postInstallScript)
      "install=true should generate zsh completions")

    (mkTest "completion-enabled-has-fish"
      (lib.hasInfix "fish" enabledResult.postInstallScript)
      "install=true should generate fish completions")

    (mkTest "completion-enabled-has-installShellCompletion"
      (lib.hasInfix "installShellCompletion" enabledResult.postInstallScript)
      "install=true should call installShellCompletion")

    (mkTest "completion-enabled-uses-pname-as-default-cmd"
      (lib.hasInfix "test-tool" enabledResult.postInstallScript)
      "install=true should use pname as default command")

    # custom command
    (mkTest "completion-custom-cmd-in-script"
      (lib.hasInfix "custom-cmd" customCmdResult.postInstallScript)
      "custom command should appear in postInstallScript")

    (mkTest "completion-custom-cmd-in-bin-path"
      (lib.hasInfix "$out/bin/custom-cmd" customCmdResult.postInstallScript)
      "custom command should appear in $out/bin path")

    (mkTest "completion-custom-cmd-not-pname"
      (!(lib.hasInfix "test-tool" customCmdResult.postInstallScript))
      "custom command should replace pname in script")

    # default command fallback
    (mkTest "completion-default-cmd-uses-pname"
      (lib.hasInfix "my-tool" defaultCmdResult.postInstallScript)
      "default command should fall back to pname")

    # return type
    (mkTest "completion-returns-attrset"
      (builtins.isAttrs enabledResult)
      "mkSwiftCompletionAttrs should return an attrset")
  ];

  # ══════════════════════════════════════════════════════════════════════
  # mkSwiftPackage + completions integration tests (12)
  # ══════════════════════════════════════════════════════════════════════
  swiftPackageCompletionTests = let
    mkPkg = swiftPkgLib.mkSwiftPackage mockPkgs;

    noCompletionPkg = mkPkg {
      pname = "no-comp-tool";
      version = "1.0.0";
      src = "/mock/src";
    };

    nullCompletionPkg = mkPkg {
      pname = "null-comp-tool";
      version = "1.0.0";
      src = "/mock/src";
      completions = null;
    };

    enabledCompletionPkg = mkPkg {
      pname = "comp-tool";
      version = "1.0.0";
      src = "/mock/src";
      completions = { install = true; };
    };

    customCmdCompletionPkg = mkPkg {
      pname = "comp-tool";
      version = "1.0.0";
      src = "/mock/src";
      completions = { install = true; command = "my-cmd"; };
    };

    disabledCompletionPkg = mkPkg {
      pname = "disabled-comp-tool";
      version = "1.0.0";
      src = "/mock/src";
      completions = { install = false; };
    };
  in [
    (mkTest "swiftpkg-comp-no-completions-no-installShellFiles"
      (!(builtins.elem "/nix/store/mock-installShellFiles" noCompletionPkg.nativeBuildInputs))
      "mkSwiftPackage without completions should not include installShellFiles")

    (mkTest "swiftpkg-comp-null-no-installShellFiles"
      (!(builtins.elem "/nix/store/mock-installShellFiles" nullCompletionPkg.nativeBuildInputs))
      "mkSwiftPackage with null completions should not include installShellFiles")

    (mkTest "swiftpkg-comp-enabled-has-installShellFiles"
      (builtins.elem "/nix/store/mock-installShellFiles" enabledCompletionPkg.nativeBuildInputs)
      "mkSwiftPackage with completions should include installShellFiles")

    (mkTest "swiftpkg-comp-enabled-installPhase-has-generate"
      (lib.hasInfix "--generate-completion-script" enabledCompletionPkg.installPhase)
      "mkSwiftPackage with completions should have completion generation in installPhase")

    (mkTest "swiftpkg-comp-enabled-installPhase-has-installShellCompletion"
      (lib.hasInfix "installShellCompletion" enabledCompletionPkg.installPhase)
      "mkSwiftPackage with completions should call installShellCompletion")

    (mkTest "swiftpkg-comp-custom-cmd-in-installPhase"
      (lib.hasInfix "my-cmd" customCmdCompletionPkg.installPhase)
      "mkSwiftPackage with custom completion command should use it in installPhase")

    (mkTest "swiftpkg-comp-disabled-no-installShellFiles"
      (!(builtins.elem "/nix/store/mock-installShellFiles" disabledCompletionPkg.nativeBuildInputs))
      "mkSwiftPackage with disabled completions should not include installShellFiles")

    (mkTest "swiftpkg-comp-disabled-no-generate-in-installPhase"
      (!(lib.hasInfix "--generate-completion-script" disabledCompletionPkg.installPhase))
      "mkSwiftPackage with disabled completions should not have completion generation")

    (mkTest "swiftpkg-comp-still-has-swift-toolchain"
      (builtins.elem "/nix/store/mock-swift-toolchain" enabledCompletionPkg.nativeBuildInputs)
      "mkSwiftPackage with completions should still include swiftToolchain")

    (mkTest "swiftpkg-comp-still-has-install"
      (lib.hasInfix "install -Dm755" enabledCompletionPkg.installPhase)
      "mkSwiftPackage with completions should still install binaries")

    (mkTest "swiftpkg-comp-nativeBuildInputs-count"
      (builtins.length enabledCompletionPkg.nativeBuildInputs == 2)
      "mkSwiftPackage with completions should have swift + installShellFiles")

    (mkTest "swiftpkg-comp-no-completion-installPhase-no-generate"
      (!(lib.hasInfix "--generate-completion-script" noCompletionPkg.installPhase))
      "mkSwiftPackage without completions should not have completion generation")
  ];

  # ══════════════════════════════════════════════════════════════════════
  # swift-tool-release.nix structural tests (10)
  # ══════════════════════════════════════════════════════════════════════
  swiftToolReleaseTests = let
    # Full functional testing requires real nixpkgs (not available in pure eval).
    # We test the file structure and its internal dependencies.
    swiftToolReleaseModule = import ../lib/swift-tool-release.nix;
  in [
    (mkTest "swift-tool-release-is-function"
      (builtins.isFunction swiftToolReleaseModule)
      "swift-tool-release.nix should export a function")

    (mkTest "swift-tool-release-lib-export-is-path"
      (builtins.isPath macosLib.swiftToolRelease)
      "lib/default.nix should export swiftToolRelease as a path")

    (mkTest "swift-tool-release-lib-export-ends-with-nix"
      (lib.hasSuffix ".nix" (toString macosLib.swiftToolRelease))
      "swiftToolRelease path should end with .nix")

    (mkTest "swift-tool-release-dep-completions"
      (builtins.isAttrs (import ../lib/completions.nix))
      "completions.nix dependency should be importable")

    (mkTest "swift-tool-release-dep-completions-has-func"
      ((import ../lib/completions.nix) ? mkSwiftCompletionAttrs)
      "completions.nix should export mkSwiftCompletionAttrs")

    (mkTest "swift-tool-release-dep-completions-func-type"
      (builtins.isFunction (import ../lib/completions.nix).mkSwiftCompletionAttrs)
      "mkSwiftCompletionAttrs should be a function")

    (mkTest "swift-tool-release-dep-overlay"
      (builtins.isAttrs (import ../lib/overlay.nix))
      "overlay.nix dependency should be importable")

    (mkTest "swift-tool-release-dep-swift-package"
      (builtins.isAttrs (import ../lib/swift-package.nix { inherit lib; }))
      "swift-package.nix dependency should be importable")

    (mkTest "swift-tool-release-dep-sandbox"
      (builtins.isAttrs (import ../lib/sandbox.nix { inherit lib; }))
      "sandbox.nix dependency should be importable")

    (mkTest "swift-tool-release-dep-sdk-helpers"
      (builtins.isAttrs (import ../lib/sdk-helpers.nix { inherit lib; }))
      "sdk-helpers.nix dependency should be importable")
  ];

  # ══════════════════════════════════════════════════════════════════════
  # Edge case tests — codesign (8)
  # ══════════════════════════════════════════════════════════════════════
  codesignEdgeTests = let
    allFalseEnt = codesignLib.mkEntitlements {};
    allTrueEnt = codesignLib.mkEntitlements {
      allowJit = true; disableLibraryValidation = true; appSandbox = true;
      networkClient = true; networkServer = true;
      fileReadAccess = true; fileWriteAccess = true;
    };
    deepEntSign = codesignLib.adHocSign {
      path = "/test"; deep = true; entitlements = "/ent.plist";
    };
    signWithEnt = codesignLib.signAllMachO {
      path = "/app"; entitlements = "/ent.plist";
    };
    signNoEnt = codesignLib.signAllMachO { path = "/app"; };
  in [
    (mkTest "codesign-edge-all-false-no-true-tag"
      (!(lib.hasInfix "<true/>" allFalseEnt))
      "mkEntitlements with all defaults should have no <true/> tags")

    (mkTest "codesign-edge-all-true-7-true-tags"
      (builtins.length (lib.splitString "<true/>" allTrueEnt) == 8)
      "mkEntitlements with all true should have exactly 7 <true/> tags")

    (mkTest "codesign-edge-deep-plus-entitlements"
      (lib.hasInfix "--deep" deepEntSign && lib.hasInfix "--entitlements" deepEntSign)
      "adHocSign with deep+entitlements should have both flags")

    (mkTest "codesign-edge-signAllMachO-ent-flag"
      (lib.hasInfix "--entitlements" signWithEnt)
      "signAllMachO with entitlements should include --entitlements")

    (mkTest "codesign-edge-signAllMachO-no-ent-no-flag"
      (!(lib.hasInfix "--entitlements" signNoEnt))
      "signAllMachO without entitlements should not include --entitlements flag")

    (mkTest "codesign-edge-signAllMachO-while-loop"
      (lib.hasInfix "while read" signNoEnt)
      "signAllMachO should use while read loop pattern")

    (mkTest "codesign-edge-adHocSign-quoted-path"
      (lib.hasInfix "\"/tmp/test\"" (codesignLib.adHocSign { path = "/tmp/test"; }))
      "adHocSign should quote the path")

    (mkTest "codesign-edge-signAllMachO-local-var"
      (lib.hasInfix "local f=" signNoEnt)
      "signAllMachO helper should use local variable")
  ];

  # ══════════════════════════════════════════════════════════════════════
  # Edge case tests — sandbox (6)
  # ══════════════════════════════════════════════════════════════════════
  sandboxEdgeTests = let
    impureXcode = sandbox.mkImpureDarwinAttrs { needsXcodebuild = true; };
    impureBoth = sandbox.mkImpureDarwinAttrs {
      needsSwiftUI = true; needsXcodebuild = true;
    };
    pureOldSDK = sandbox.mkPureSDKInputs mockPkgsOldSDK;
  in [
    (mkTest "sandbox-edge-xcodebuild-noChroot"
      (impureXcode.__noChroot == true)
      "mkImpureDarwinAttrs with needsXcodebuild should set __noChroot")

    (mkTest "sandbox-edge-xcodebuild-has-hostDeps"
      (builtins.isList impureXcode.impureHostDeps
        && impureXcode.impureHostDeps != [])
      "mkImpureDarwinAttrs with needsXcodebuild should have non-empty hostDeps")

    (mkTest "sandbox-edge-both-has-sdkroot-and-swiftui"
      (lib.hasInfix "SDKROOT" impureBoth.preBuild
        && lib.hasInfix "SwiftUI" impureBoth.preBuild)
      "mkImpureDarwinAttrs with both flags should have sdkroot and swiftUI check")

    (mkTest "sandbox-edge-old-sdk-has-security"
      (builtins.elem "mock-Security" pureOldSDK)
      "mkPureSDKInputs old SDK should include Security framework")

    (mkTest "sandbox-edge-old-sdk-has-system-config"
      (builtins.elem "mock-SystemConfiguration" pureOldSDK)
      "mkPureSDKInputs old SDK should include SystemConfiguration framework")

    (mkTest "sandbox-edge-old-sdk-no-apple-sdk"
      (!(builtins.elem "/nix/store/mock-apple-sdk" pureOldSDK))
      "mkPureSDKInputs old SDK should not have apple-sdk")
  ];

  # ══════════════════════════════════════════════════════════════════════
  # Edge case tests — mkSwiftPackage (10)
  # ══════════════════════════════════════════════════════════════════════
  swiftPackageEdgeTests = let
    mkPkg = swiftPkgLib.mkSwiftPackage mockPkgs;

    defaultPkg = mkPkg {
      pname = "edge-tool"; version = "1.0.0"; src = "/mock/src";
    };

    extraAttrPkg = mkPkg {
      pname = "extra-tool"; version = "1.0.0"; src = "/mock/src";
      customAttr = "preserved";
    };

    extraBuildInputsPkg = mkPkg {
      pname = "extra-bi-tool"; version = "1.0.0"; src = "/mock/src";
      extraBuildInputs = [ "extra-dep-1" "extra-dep-2" ];
    };

    withExtraNativePkg = mkPkg {
      pname = "extra-native-tool"; version = "1.0.0"; src = "/mock/src";
      nativeBuildInputs = [ "extra-native" ];
    };
  in [
    (mkTest "swiftpkg-edge-extra-attr-preserved"
      (extraAttrPkg ? customAttr && extraAttrPkg.customAttr == "preserved")
      "mkSwiftPackage should preserve extra passthrough attributes")

    (mkTest "swiftpkg-edge-buildInputs-has-apple-sdk"
      (builtins.elem "/nix/store/mock-apple-sdk" defaultPkg.buildInputs)
      "mkSwiftPackage pure build should include apple-sdk in buildInputs")

    (mkTest "swiftpkg-edge-extraBuildInputs-forwarded"
      (builtins.elem "extra-dep-1" extraBuildInputsPkg.buildInputs
        && builtins.elem "extra-dep-2" extraBuildInputsPkg.buildInputs)
      "mkSwiftPackage should forward extraBuildInputs to buildInputs")

    (mkTest "swiftpkg-edge-extra-nativeBuildInputs-preserved"
      (builtins.elem "extra-native" withExtraNativePkg.nativeBuildInputs)
      "mkSwiftPackage should preserve extra nativeBuildInputs from cleanArgs")

    (mkTest "swiftpkg-edge-installPhase-mkdir"
      (lib.hasInfix "mkdir -p $out/bin" defaultPkg.installPhase)
      "mkSwiftPackage installPhase should create $out/bin")

    (mkTest "swiftpkg-edge-pure-no-sdkroot-in-buildPhase"
      (!(lib.hasInfix "SDKROOT" defaultPkg.buildPhase))
      "mkSwiftPackage pure build should not have SDKROOT discovery")

    (mkTest "swiftpkg-edge-buildPhase-runHook-preBuild"
      (lib.hasInfix "runHook preBuild" defaultPkg.buildPhase)
      "mkSwiftPackage buildPhase should call runHook preBuild")

    (mkTest "swiftpkg-edge-buildPhase-runHook-postBuild"
      (lib.hasInfix "runHook postBuild" defaultPkg.buildPhase)
      "mkSwiftPackage buildPhase should call runHook postBuild")

    (mkTest "swiftpkg-edge-installPhase-runHook-preInstall"
      (lib.hasInfix "runHook preInstall" defaultPkg.installPhase)
      "mkSwiftPackage installPhase should call runHook preInstall")

    (mkTest "swiftpkg-edge-installPhase-runHook-postInstall"
      (lib.hasInfix "runHook postInstall" defaultPkg.installPhase)
      "mkSwiftPackage installPhase should call runHook postInstall")
  ];

  # ══════════════════════════════════════════════════════════════════════
  # Edge case tests — mkSwiftApp (8)
  # ══════════════════════════════════════════════════════════════════════
  swiftAppEdgeTests = let
    mkApp = swiftAppLib.mkSwiftApp mockPkgs;

    customEntApp = mkApp {
      pname = "EntApp"; version = "1.0.0"; src = "/mock/src";
      bundleIdentifier = "io.pleme.ent";
      entitlements = { allowJit = true; };
    };

    defaultApp = mkApp {
      pname = "DefaultApp"; version = "1.0.0"; src = "/mock/src";
      bundleIdentifier = "io.pleme.default";
    };

    noSwiftUIApp = mkApp {
      pname = "NoUIApp"; version = "1.0.0"; src = "/mock/src";
      bundleIdentifier = "io.pleme.noui";
      needsSwiftUI = false;
    };

    debugApp = mkApp {
      pname = "DebugApp"; version = "2.0.0"; src = "/mock/src";
      bundleIdentifier = "io.pleme.debug";
      buildConfiguration = "debug";
    };
  in [
    (mkTest "swiftapp-edge-custom-ent-has-jit"
      (lib.hasInfix "allow-jit" customEntApp.postFixup)
      "mkSwiftApp with custom entitlements should include allowJit")

    (mkTest "swiftapp-edge-custom-ent-has-disable-lib-val"
      (lib.hasInfix "disable-library-validation" customEntApp.postFixup)
      "mkSwiftApp should always include default disableLibraryValidation")

    (mkTest "swiftapp-edge-postFixup-has-entFile"
      (lib.hasInfix "entFile" defaultApp.postFixup)
      "mkSwiftApp postFixup should define entFile for entitlements")

    (mkTest "swiftapp-edge-postFixup-signAllMachO-path"
      (lib.hasInfix "Applications/DefaultApp.app" defaultApp.postFixup)
      "mkSwiftApp postFixup should sign the correct app path")

    (mkTest "swiftapp-edge-always-impure"
      (defaultApp.__noChroot == true)
      "mkSwiftApp should always be impure")

    (mkTest "swiftapp-edge-no-swiftui-no-check"
      (!(lib.hasInfix "SwiftUI.framework" noSwiftUIApp.buildPhase))
      "mkSwiftApp with needsSwiftUI=false should not check SwiftUI")

    (mkTest "swiftapp-edge-debug-config"
      (lib.hasInfix "-c debug" debugApp.buildPhase)
      "mkSwiftApp should use custom buildConfiguration")

    (mkTest "swiftapp-edge-installPhase-appDir"
      (lib.hasInfix "appDir=" defaultApp.installPhase)
      "mkSwiftApp installPhase should set appDir variable")
  ];

  # ══════════════════════════════════════════════════════════════════════
  # Edge case tests — mkZigSwiftApp (6)
  # ══════════════════════════════════════════════════════════════════════
  zigSwiftAppEdgeTests = let
    mkZigApp = zigSwiftLib.mkZigSwiftApp mockPkgs;

    defaultZigApp = mkZigApp {
      pname = "TestApp"; version = "1.0.0"; src = "/mock/src";
    };

    extraApp = mkZigApp {
      pname = "ExtraApp"; version = "1.0.0"; src = "/mock/src";
      extraNativeBuildInputs = [ "extra-native" ];
      extraBuildInputs = [ "extra-build" ];
    };
  in [
    (mkTest "zigswift-edge-default-ent-has-jit-and-lib-val"
      (lib.hasInfix "allow-jit" defaultZigApp.postFixup
        && lib.hasInfix "disable-library-validation" defaultZigApp.postFixup)
      "mkZigSwiftApp default entitlements should have JIT and disable-library-validation")

    (mkTest "zigswift-edge-extra-nativeBuildInputs"
      (builtins.elem "extra-native" extraApp.nativeBuildInputs)
      "mkZigSwiftApp should forward extraNativeBuildInputs")

    (mkTest "zigswift-edge-extra-buildInputs"
      (builtins.elem "extra-build" extraApp.buildInputs)
      "mkZigSwiftApp should forward extraBuildInputs")

    (mkTest "zigswift-edge-default-needsSwiftUI"
      (lib.hasInfix "SwiftUI.framework" defaultZigApp.buildPhase)
      "mkZigSwiftApp should check SwiftUI by default (needsSwiftUI=true)")

    (mkTest "zigswift-edge-has-both-toolchains"
      (builtins.elem "/nix/store/mock-zig-toolchain" defaultZigApp.nativeBuildInputs
        && builtins.elem "/nix/store/mock-swift-toolchain" defaultZigApp.nativeBuildInputs)
      "mkZigSwiftApp should include both zig and swift in nativeBuildInputs")

    (mkTest "zigswift-edge-signs-standalone-binaries"
      (lib.hasInfix "$out/bin" defaultZigApp.postFixup)
      "mkZigSwiftApp postFixup should sign standalone binaries")
  ];

  # ══════════════════════════════════════════════════════════════════════
  # Edge case tests — mkXcodeProject (8)
  # ══════════════════════════════════════════════════════════════════════
  xcodeProjectEdgeTests = let
    mkXcode = xcodeProjLib.mkXcodeProject mockPkgs;

    minimalXcode = mkXcode {
      pname = "MinApp"; version = "1.0.0"; src = "/mock/src";
      scheme = "MinApp";
    };

    extraFlagsXcode = mkXcode {
      pname = "FlagApp"; version = "1.0.0"; src = "/mock/src";
      scheme = "FlagApp";
      extraXcodebuildFlags = [ "SWIFT_VERSION=5.9" "MACOSX_DEPLOYMENT_TARGET=14.0" ];
    };

    customDerivedData = mkXcode {
      pname = "DDApp"; version = "1.0.0"; src = "/mock/src";
      scheme = "DDApp";
      derivedDataPath = "/custom/derived";
    };
  in [
    (mkTest "xcode-edge-no-workspace-no-project"
      (!(lib.hasInfix "-workspace" minimalXcode.buildPhase)
        && !(lib.hasInfix "-project" minimalXcode.buildPhase))
      "mkXcodeProject without workspace/project should have neither flag")

    (mkTest "xcode-edge-extra-flags"
      (lib.hasInfix "SWIFT_VERSION=5.9" extraFlagsXcode.buildPhase)
      "mkXcodeProject should include extraXcodebuildFlags")

    (mkTest "xcode-edge-extra-flags-deployment-target"
      (lib.hasInfix "MACOSX_DEPLOYMENT_TARGET=14.0" extraFlagsXcode.buildPhase)
      "mkXcodeProject extraXcodebuildFlags should include deployment target")

    (mkTest "xcode-edge-derived-data-path"
      (lib.hasInfix "/custom/derived" customDerivedData.buildPhase)
      "mkXcodeProject should use custom derivedDataPath")

    (mkTest "xcode-edge-only-active-arch"
      (lib.hasInfix "ONLY_ACTIVE_ARCH=NO" minimalXcode.buildPhase)
      "mkXcodeProject should include ONLY_ACTIVE_ARCH=NO")

    (mkTest "xcode-edge-code-signing-allowed"
      (lib.hasInfix "CODE_SIGNING_ALLOWED=NO" minimalXcode.buildPhase)
      "mkXcodeProject should include CODE_SIGNING_ALLOWED=NO")

    (mkTest "xcode-edge-scheme-in-buildPhase"
      (lib.hasInfix "MinApp" minimalXcode.buildPhase)
      "mkXcodeProject should include scheme in buildPhase")

    (mkTest "xcode-edge-installPhase-error-handling"
      (lib.hasInfix "Could not find .app" minimalXcode.installPhase)
      "mkXcodeProject installPhase should have error handling for missing app")
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
  ++ completionTests
  ++ swiftPackageCompletionTests
  ++ swiftToolReleaseTests
  ++ codesignEdgeTests
  ++ sandboxEdgeTests
  ++ swiftPackageEdgeTests
  ++ swiftAppEdgeTests
  ++ zigSwiftAppEdgeTests
  ++ xcodeProjectEdgeTests
)
