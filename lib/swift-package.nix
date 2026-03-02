# mkSwiftPackage — build Swift Package Manager (SPM) packages
#
# Builds SPM CLI tools and libraries using `swift build`.
# Pure by default (uses nixpkgs apple-sdk). Set needsSwiftUI = true for impure.
#
# Usage:
#   pkgs.mkSwiftPackage {
#     pname = "my-tool";
#     version = "1.0.0";
#     src = ./.;
#   }
{ lib }:

let
  sandbox = import ./sandbox.nix { inherit lib; };
  sdkHelpers = import ./sdk-helpers.nix { inherit lib; };
in
{
  mkSwiftPackage = pkgs: {
    pname,
    version,
    src,
    swiftFlags ? [],
    buildConfiguration ? "release",
    needsSwiftUI ? false,
    extraBuildInputs ? [],
    products ? [ pname ],
    ...
  } @ args:
  let
    impureAttrs = lib.optionalAttrs needsSwiftUI
      (sandbox.mkImpureDarwinAttrs { inherit needsSwiftUI; });

    pureSDK = lib.optionals (!needsSwiftUI) (sandbox.mkPureSDKInputs pkgs);

    flagStr = lib.concatStringsSep " " (
      [ "-c" buildConfiguration "--disable-sandbox" ]
      ++ swiftFlags
    );

    cleanArgs = builtins.removeAttrs args [
      "pname" "version" "src" "swiftFlags" "buildConfiguration"
      "needsSwiftUI" "extraBuildInputs" "products"
    ];
  in
  pkgs.stdenv.mkDerivation (cleanArgs // {
    inherit pname version src;

    nativeBuildInputs = [ pkgs.swiftToolchain ] ++ (cleanArgs.nativeBuildInputs or []);
    buildInputs = pureSDK ++ extraBuildInputs ++ (cleanArgs.buildInputs or []);

    buildPhase = ''
      runHook preBuild
      ${lib.optionalString needsSwiftUI sdkHelpers.sdkrootDiscoveryScript}
      swift build ${flagStr}
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      ${lib.concatMapStringsSep "\n" (prod: ''
        install -Dm755 ".build/${buildConfiguration}/${prod}" "$out/bin/${prod}"
      '') products}
      runHook postInstall
    '';

    meta = {
      platforms = [ "x86_64-darwin" "aarch64-darwin" ];
    } // (cleanArgs.meta or {});
  } // impureAttrs);
}
