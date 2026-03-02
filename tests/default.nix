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

  # ── codesign.nix tests ──────────────────────────────────────────────
  codesignTests = [
    (mkTest "codesign-adHocSign-returns-string"
      (builtins.isString (codesignLib.adHocSign { path = "/tmp/test"; }))
      "adHocSign should return a string")

    (mkTest "codesign-adHocSign-contains-codesign"
      (lib.hasInfix "/usr/bin/codesign" (codesignLib.adHocSign { path = "/tmp/test"; }))
      "adHocSign should call /usr/bin/codesign")

    (mkTest "codesign-adHocSign-contains-path"
      (lib.hasInfix "/tmp/test" (codesignLib.adHocSign { path = "/tmp/test"; }))
      "adHocSign should include the target path")

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

    (mkTest "codesign-mkEntitlements-returns-string"
      (builtins.isString (codesignLib.mkEntitlements {}))
      "mkEntitlements should return a string")

    (mkTest "codesign-mkEntitlements-valid-plist-header"
      (lib.hasInfix "<?xml version" (codesignLib.mkEntitlements {}))
      "mkEntitlements should produce XML plist header")

    (mkTest "codesign-mkEntitlements-plist-dict"
      (lib.hasInfix "<dict>" (codesignLib.mkEntitlements {}))
      "mkEntitlements should contain <dict> element")

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

    (mkTest "codesign-signAllMachO-returns-string"
      (builtins.isString (codesignLib.signAllMachO { path = "/tmp/app"; }))
      "signAllMachO should return a string")

    (mkTest "codesign-signAllMachO-uses-file-command"
      (lib.hasInfix "/usr/bin/file" (codesignLib.signAllMachO { path = "/tmp/app"; }))
      "signAllMachO should use /usr/bin/file to detect Mach-O")

    (mkTest "codesign-signAllMachO-uses-find"
      (lib.hasInfix "find" (codesignLib.signAllMachO { path = "/tmp/app"; }))
      "signAllMachO should use find to walk directory")

    (mkTest "codesign-signAllMachO-chmod-pattern"
      (lib.hasInfix "chmod u+w" (codesignLib.signAllMachO { path = "/tmp/app"; }))
      "signAllMachO should chmod u+w before signing")

    (mkTest "codesign-signAllMachO-restore-perms"
      (lib.hasInfix "chmod u-w" (codesignLib.signAllMachO { path = "/tmp/app"; }))
      "signAllMachO should chmod u-w after signing")
  ];

  # ── sdk-helpers.nix tests ───────────────────────────────────────────
  sdkTests = [
    (mkTest "sdk-xcodeSDKPaths-is-list"
      (builtins.isList sdkHelpers.xcodeSDKPaths)
      "xcodeSDKPaths should be a list")

    (mkTest "sdk-xcodeSDKPaths-not-empty"
      (sdkHelpers.xcodeSDKPaths != [])
      "xcodeSDKPaths should not be empty")

    (mkTest "sdk-xcodeSDKPaths-contains-xcode-path"
      (builtins.any (p: lib.hasInfix "Xcode.app" p) sdkHelpers.xcodeSDKPaths)
      "xcodeSDKPaths should contain Xcode.app path")

    (mkTest "sdk-xcodeSDKPaths-contains-clt-path"
      (builtins.any (p: lib.hasInfix "CommandLineTools" p) sdkHelpers.xcodeSDKPaths)
      "xcodeSDKPaths should contain CommandLineTools path")

    (mkTest "sdk-impureHostDeps-is-list"
      (builtins.isList sdkHelpers.impureHostDeps)
      "impureHostDeps should be a list")

    (mkTest "sdk-impureHostDeps-contains-usr-lib"
      (builtins.elem "/usr/lib" sdkHelpers.impureHostDeps)
      "impureHostDeps should include /usr/lib")

    (mkTest "sdk-impureHostDeps-contains-frameworks"
      (builtins.elem "/System/Library/Frameworks" sdkHelpers.impureHostDeps)
      "impureHostDeps should include /System/Library/Frameworks")

    (mkTest "sdk-sdkrootDiscoveryScript-is-string"
      (builtins.isString sdkHelpers.sdkrootDiscoveryScript)
      "sdkrootDiscoveryScript should be a string")

    (mkTest "sdk-sdkrootDiscoveryScript-uses-xcrun"
      (lib.hasInfix "xcrun" sdkHelpers.sdkrootDiscoveryScript)
      "sdkrootDiscoveryScript should try xcrun first")

    (mkTest "sdk-sdkrootDiscoveryScript-exports-SDKROOT"
      (lib.hasInfix "export SDKROOT" sdkHelpers.sdkrootDiscoveryScript)
      "sdkrootDiscoveryScript should export SDKROOT")

    (mkTest "sdk-swiftUIAvailabilityCheck-is-string"
      (builtins.isString sdkHelpers.swiftUIAvailabilityCheck)
      "swiftUIAvailabilityCheck should be a string")

    (mkTest "sdk-swiftUIAvailabilityCheck-checks-framework"
      (lib.hasInfix "SwiftUI.framework" sdkHelpers.swiftUIAvailabilityCheck)
      "swiftUIAvailabilityCheck should check for SwiftUI.framework")
  ];

  # ── sandbox.nix tests ──────────────────────────────────────────────
  sandboxTests = let
    impureDefault = sandbox.mkImpureDarwinAttrs {};
    impureSwiftUI = sandbox.mkImpureDarwinAttrs { needsSwiftUI = true; };
  in [
    (mkTest "sandbox-impure-noChroot"
      (impureDefault.__noChroot == true)
      "mkImpureDarwinAttrs should set __noChroot = true")

    (mkTest "sandbox-impure-has-hostDeps"
      (builtins.isList impureDefault.impureHostDeps)
      "mkImpureDarwinAttrs should include impureHostDeps")

    (mkTest "sandbox-impure-has-preBuild"
      (builtins.isString impureDefault.preBuild)
      "mkImpureDarwinAttrs should set preBuild script")

    (mkTest "sandbox-impure-preBuild-has-sdkroot"
      (lib.hasInfix "SDKROOT" impureDefault.preBuild)
      "mkImpureDarwinAttrs preBuild should discover SDKROOT")

    (mkTest "sandbox-impure-swiftui-checks-framework"
      (lib.hasInfix "SwiftUI.framework" impureSwiftUI.preBuild)
      "mkImpureDarwinAttrs with needsSwiftUI should check for SwiftUI.framework")

    (mkTest "sandbox-impure-default-no-swiftui-check"
      (!(lib.hasInfix "SwiftUI.framework" impureDefault.preBuild))
      "mkImpureDarwinAttrs without needsSwiftUI should not check for SwiftUI.framework")
  ];

  # ── overlay.nix tests ──────────────────────────────────────────────
  overlayTests = [
    (mkTest "overlay-mkSwiftOverlay-is-function"
      (builtins.isFunction overlayLib.mkSwiftOverlay)
      "mkSwiftOverlay should be a function")

    (mkTest "overlay-mkSwiftOverlay-returns-function"
      (builtins.isFunction (overlayLib.mkSwiftOverlay {}))
      "mkSwiftOverlay {} should return an overlay function")
  ];

  # ── lib export structure tests (ensures no typos/missing files) ────
  libStructureTests = [
    (mkTest "lib-codesign-has-adHocSign"
      (codesignLib ? adHocSign)
      "codesign.nix should export adHocSign")

    (mkTest "lib-codesign-has-mkEntitlements"
      (codesignLib ? mkEntitlements)
      "codesign.nix should export mkEntitlements")

    (mkTest "lib-codesign-has-signAllMachO"
      (codesignLib ? signAllMachO)
      "codesign.nix should export signAllMachO")

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

    (mkTest "lib-sandbox-has-mkImpureDarwinAttrs"
      (sandbox ? mkImpureDarwinAttrs)
      "sandbox.nix should export mkImpureDarwinAttrs")

    (mkTest "lib-sandbox-has-mkPureSDKInputs"
      (sandbox ? mkPureSDKInputs)
      "sandbox.nix should export mkPureSDKInputs")

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
  ];

  # ── module evaluation tests ────────────────────────────────────────
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

    # Default (disabled)
    defaultResult = evalModule {};
    # Enabled on Darwin
    darwinEnabled = evalModule { isDarwin = true; enableMacos = true; };
    # Enabled on Darwin with swift disabled
    darwinNoSwift = evalModule { isDarwin = true; enableMacos = true; enableSwift = false; };
    # Enabled on Linux (should no-op)
    linuxEnabled = evalModule { isDarwin = false; enableMacos = true; };
  in [
    (mkTest "module-has-macos-option"
      (defaultResult.options ? blackmatter)
      "module should define blackmatter option namespace")

    (mkTest "module-macos-enable-default-false"
      (defaultResult.config.blackmatter.components.macos.enable == false)
      "blackmatter.components.macos.enable should default to false")

    (mkTest "module-swift-enable-default-true"
      (defaultResult.config.blackmatter.components.macos.swift.enable == true)
      "blackmatter.components.macos.swift.enable should default to true")

    (mkTest "module-disabled-no-packages"
      (defaultResult.config.home.packages == [])
      "disabled module should add no packages")

    (mkTest "module-darwin-enabled-has-packages"
      (darwinEnabled.config.home.packages != [])
      "enabled on Darwin should add packages")

    (mkTest "module-darwin-enabled-one-package"
      (builtins.length darwinEnabled.config.home.packages == 1)
      "enabled on Darwin should add exactly 1 package (swiftToolchain)")

    (mkTest "module-darwin-no-swift-no-packages"
      (darwinNoSwift.config.home.packages == [])
      "enabled on Darwin with swift.enable=false should add no packages")

    (mkTest "module-linux-enabled-no-packages"
      (linuxEnabled.config.home.packages == [])
      "enabled on Linux should add no packages (Darwin-only)")
  ];

in
runTests (
  codesignTests
  ++ sdkTests
  ++ sandboxTests
  ++ overlayTests
  ++ libStructureTests
  ++ moduleTests
)
