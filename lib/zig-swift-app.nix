# mkZigSwiftApp — build macOS apps with Zig core + Swift GUI
#
# For the Ghostty pattern: Zig builds the core library, Swift provides the
# macOS GUI shell (AppKit/SwiftUI). Impure build with system SDK.
#
# Usage:
#   pkgs.mkZigSwiftApp {
#     pname = "Ghostty";
#     version = "1.0.0";
#     src = fetchFromGitHub { ... };
#     zigBuildFlags = [ "-Doptimize=ReleaseFast" ];
#   }
{ lib }:

let
  sandbox = import ./sandbox.nix { inherit lib; };
  sdkHelpers = import ./sdk-helpers.nix { inherit lib; };
  codesignLib = import ./codesign.nix { inherit lib; };
in
{
  mkZigSwiftApp = pkgs: {
    pname,
    version,
    src,
    bundleIdentifier ? "io.pleme.${lib.toLower pname}",
    zigBuildFlags ? [],
    needsSwiftUI ? true,
    codesign ? true,
    entitlements ? {},
    extraNativeBuildInputs ? [],
    extraBuildInputs ? [],
    buildPhaseOverride ? null,
    installPhaseOverride ? null,
    ...
  } @ args:
  let
    impureAttrs = sandbox.mkImpureDarwinAttrs {
      inherit needsSwiftUI;
      needsXcodebuild = false;
    };

    zigFlags = lib.concatStringsSep " " zigBuildFlags;

    entitlementsPlist = lib.optionalString codesign
      (codesignLib.mkEntitlements ({
        disableLibraryValidation = true;
        allowJit = true;
      } // entitlements));

    cleanArgs = builtins.removeAttrs args [
      "pname" "version" "src" "bundleIdentifier" "zigBuildFlags"
      "needsSwiftUI" "codesign" "entitlements" "extraNativeBuildInputs"
      "extraBuildInputs" "buildPhaseOverride" "installPhaseOverride"
    ];
  in
  pkgs.stdenv.mkDerivation (cleanArgs // {
    inherit pname version src;

    nativeBuildInputs = [
      pkgs.zigToolchain
      pkgs.swiftToolchain
    ] ++ extraNativeBuildInputs ++ (cleanArgs.nativeBuildInputs or []);

    buildInputs = extraBuildInputs ++ (cleanArgs.buildInputs or []);

    buildPhase = if buildPhaseOverride != null then buildPhaseOverride else ''
      runHook preBuild
      ${sdkHelpers.sdkrootDiscoveryScript}
      ${lib.optionalString needsSwiftUI sdkHelpers.swiftUIAvailabilityCheck}

      # Build with Zig (uses both Zig and Swift compilers)
      zig build ${zigFlags} \
        --prefix "$out" \
        -Doptimize=ReleaseFast \
        2>&1
      runHook postBuild
    '';

    installPhase = if installPhaseOverride != null then installPhaseOverride else ''
      runHook preInstall

      # If zig build already created the .app bundle in $out, we're done.
      # Otherwise look for it in zig-out/
      if [ ! -d "$out/Applications" ] && [ -d "zig-out" ]; then
        mkdir -p "$out/Applications"
        cp -r zig-out/*.app "$out/Applications/" 2>/dev/null || true
      fi

      # Also install CLI binary if present
      if [ -d "zig-out/bin" ]; then
        mkdir -p "$out/bin"
        cp -r zig-out/bin/* "$out/bin/" || true
      fi

      runHook postInstall
    '';

    postFixup = lib.optionalString codesign ''
      ${lib.optionalString (entitlementsPlist != "") ''
        entFile=$(mktemp)
        cat > "$entFile" << 'ENTEOF'
        ${entitlementsPlist}
        ENTEOF
      ''}
      # Sign all .app bundles
      for app in "$out"/Applications/*.app; do
        if [ -d "$app" ]; then
          ${codesignLib.signAllMachO { path = "$app"; }}
        fi
      done
      # Sign standalone binaries
      if [ -d "$out/bin" ]; then
        ${codesignLib.signAllMachO { path = "$out/bin"; }}
      fi
    '' + (cleanArgs.postFixup or "");

    meta = {
      platforms = [ "x86_64-darwin" "aarch64-darwin" ];
    } // (cleanArgs.meta or {});
  } // impureAttrs);
}
