# mkSwiftApp — build macOS .app bundles from Swift source
#
# Creates proper .app bundle structure with Info.plist, ad-hoc codesigning,
# and optional entitlements. Uses impure build by default (most .app bundles
# need SwiftUI or system frameworks).
#
# Usage:
#   pkgs.mkSwiftApp {
#     pname = "MyApp";
#     version = "1.0.0";
#     src = ./.;
#     bundleIdentifier = "io.pleme.myapp";
#   }
{ lib }:

let
  sandbox = import ./sandbox.nix { inherit lib; };
  sdkHelpers = import ./sdk-helpers.nix { inherit lib; };
  codesignLib = import ./codesign.nix { inherit lib; };
in
{
  mkSwiftApp = pkgs: {
    pname,
    version,
    src,
    bundleIdentifier,
    swiftFlags ? [],
    buildConfiguration ? "release",
    needsSwiftUI ? true,
    frameworks ? [],
    codesign ? true,
    entitlements ? {},
    minimumDeploymentTarget ? "14.0",
    extraBuildInputs ? [],
    ...
  } @ args:
  let
    impureAttrs = sandbox.mkImpureDarwinAttrs { inherit needsSwiftUI; };

    frameworkFlags = lib.concatMapStringsSep " " (f: "-Xlinker -framework -Xlinker ${f}") frameworks;

    flagStr = lib.concatStringsSep " " (
      [ "-c" buildConfiguration "--disable-sandbox" ]
      ++ swiftFlags
      ++ lib.optional (frameworks != []) frameworkFlags
    );

    infoPlist = pkgs.writeText "Info.plist" ''
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleName</key>
        <string>${pname}</string>
        <key>CFBundleDisplayName</key>
        <string>${pname}</string>
        <key>CFBundleIdentifier</key>
        <string>${bundleIdentifier}</string>
        <key>CFBundleVersion</key>
        <string>${version}</string>
        <key>CFBundleShortVersionString</key>
        <string>${version}</string>
        <key>CFBundleExecutable</key>
        <string>${pname}</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>LSMinimumSystemVersion</key>
        <string>${minimumDeploymentTarget}</string>
        <key>NSHighResolutionCapable</key>
        <true/>
        <key>NSSupportsAutomaticTermination</key>
        <true/>
      </dict>
      </plist>
    '';

    entitlementsPlist = lib.optionalString codesign
      (codesignLib.mkEntitlements ({
        disableLibraryValidation = true;
      } // entitlements));

    cleanArgs = builtins.removeAttrs args [
      "pname" "version" "src" "bundleIdentifier" "swiftFlags"
      "buildConfiguration" "needsSwiftUI" "frameworks" "codesign"
      "entitlements" "minimumDeploymentTarget" "extraBuildInputs"
    ];
  in
  pkgs.stdenv.mkDerivation (cleanArgs // {
    inherit pname version src;

    nativeBuildInputs = [ pkgs.swiftToolchain ] ++ (cleanArgs.nativeBuildInputs or []);
    buildInputs = extraBuildInputs ++ (cleanArgs.buildInputs or []);

    buildPhase = ''
      runHook preBuild
      ${sdkHelpers.sdkrootDiscoveryScript}
      ${lib.optionalString needsSwiftUI sdkHelpers.swiftUIAvailabilityCheck}
      swift build ${flagStr}
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      # Create .app bundle structure
      appDir="$out/Applications/${pname}.app"
      mkdir -p "$appDir/Contents/MacOS"
      mkdir -p "$appDir/Contents/Resources"

      # Copy binary
      install -Dm755 ".build/${buildConfiguration}/${pname}" "$appDir/Contents/MacOS/${pname}"

      # Install Info.plist
      cp ${infoPlist} "$appDir/Contents/Info.plist"

      # Copy Resources if they exist in source
      if [ -d "Resources" ]; then
        cp -r Resources/* "$appDir/Contents/Resources/" || true
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
      ${codesignLib.signAllMachO { path = "$out/Applications/${pname}.app"; }}
    '' + (cleanArgs.postFixup or "");

    meta = {
      platforms = [ "x86_64-darwin" "aarch64-darwin" ];
    } // (cleanArgs.meta or {});
  } // impureAttrs);
}
