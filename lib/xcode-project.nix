# mkXcodeProject — build .xcodeproj / .xcworkspace projects
#
# Wraps system /usr/bin/xcodebuild with __noChroot for projects that
# can't be converted to SPM. Uses ad-hoc signing (CODE_SIGN_IDENTITY="-").
#
# Usage:
#   pkgs.mkXcodeProject {
#     pname = "MyApp";
#     version = "1.0.0";
#     src = ./.;
#     scheme = "MyApp";
#   }
{ lib }:

let
  sandbox = import ./sandbox.nix { inherit lib; };
  sdkHelpers = import ./sdk-helpers.nix { inherit lib; };
  codesignLib = import ./codesign.nix { inherit lib; };
in
{
  mkXcodeProject = pkgs: {
    pname,
    version,
    src,
    scheme,
    configuration ? "Release",
    workspace ? null,
    project ? null,
    derivedDataPath ? "$TMPDIR/DerivedData",
    codesign ? true,
    entitlements ? {},
    extraXcodebuildFlags ? [],
    ...
  } @ args:
  let
    impureAttrs = sandbox.mkImpureDarwinAttrs {
      needsSwiftUI = true;
      needsXcodebuild = true;
    };

    targetFlag =
      if workspace != null then "-workspace \"${workspace}\""
      else if project != null then "-project \"${project}\""
      else "";

    xcodebuildFlags = lib.concatStringsSep " " ([
      targetFlag
      "-scheme \"${scheme}\""
      "-configuration ${configuration}"
      "-derivedDataPath \"${derivedDataPath}\""
      "CODE_SIGN_IDENTITY=\"-\""
      "CODE_SIGNING_REQUIRED=NO"
      "CODE_SIGNING_ALLOWED=NO"
      "ONLY_ACTIVE_ARCH=NO"
    ] ++ extraXcodebuildFlags);

    entitlementsPlist = lib.optionalString codesign
      (codesignLib.mkEntitlements ({
        disableLibraryValidation = true;
      } // entitlements));

    cleanArgs = builtins.removeAttrs args [
      "pname" "version" "src" "scheme" "configuration" "workspace"
      "project" "derivedDataPath" "codesign" "entitlements"
      "extraXcodebuildFlags"
    ];
  in
  pkgs.stdenvNoCC.mkDerivation (cleanArgs // {
    inherit pname version src;

    buildPhase = ''
      runHook preBuild
      ${sdkHelpers.sdkrootDiscoveryScript}

      /usr/bin/xcodebuild build ${xcodebuildFlags}
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      # Find and copy the built .app bundle
      appPath=$(find "${derivedDataPath}" -name "*.app" -type d -path "*/Build/Products/${configuration}*" -print -quit)
      if [ -z "$appPath" ]; then
        echo "ERROR: Could not find .app bundle in DerivedData" >&2
        find "${derivedDataPath}" -name "*.app" -type d | head -5
        exit 1
      fi

      mkdir -p "$out/Applications"
      cp -r "$appPath" "$out/Applications/"
      runHook postInstall
    '';

    postFixup = lib.optionalString codesign ''
      ${lib.optionalString (entitlementsPlist != "") ''
        entFile=$(mktemp)
        cat > "$entFile" << 'ENTEOF'
        ${entitlementsPlist}
        ENTEOF
      ''}
      for app in "$out"/Applications/*.app; do
        if [ -d "$app" ]; then
          ${codesignLib.signAllMachO { path = "$app"; }}
        fi
      done
    '' + (cleanArgs.postFixup or "");

    meta = {
      platforms = [ "x86_64-darwin" "aarch64-darwin" ];
    } // (cleanArgs.meta or {});
  } // impureAttrs);
}
