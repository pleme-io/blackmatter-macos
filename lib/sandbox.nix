# Sandbox Helpers — Darwin impure build support
#
# Provides attribute sets for Nix derivations that need to escape the sandbox
# to access system frameworks (SwiftUI, Xcode SDK, xcodebuild).
#
# Two modes:
#   - Pure: uses nixpkgs apple-sdk for Foundation/AppKit (sandboxed)
#   - Impure: uses __noChroot + impureHostDeps for SwiftUI/Xcode (unsandboxed)
{ lib }:

let
  sdkHelpers = import ./sdk-helpers.nix { inherit lib; };
in
{
  # Returns derivation attrs for impure Darwin builds that need system SDK access.
  #
  # Usage in a derivation:
  #   mkDerivation ({
  #     ...
  #   } // sandbox.mkImpureDarwinAttrs { needsSwiftUI = true; })
  mkImpureDarwinAttrs = {
    needsSwiftUI ? false,
    needsXcodebuild ? false,
  }: {
    __noChroot = true;
    impureHostDeps = sdkHelpers.impureHostDeps;

    # Inject SDK discovery into the build
    preBuild = lib.concatStringsSep "\n" (
      [ sdkHelpers.sdkrootDiscoveryScript ]
      ++ lib.optional needsSwiftUI sdkHelpers.swiftUIAvailabilityCheck
    );
  };

  # Returns buildInputs for pure SDK builds (Foundation, AppKit, etc.)
  #
  # Usage:
  #   buildInputs = sandbox.mkPureSDKInputs pkgs;
  mkPureSDKInputs = pkgs:
    if pkgs ? apple-sdk then [ pkgs.apple-sdk ]
    else lib.optionals (pkgs ? darwin)
      (with pkgs.darwin.apple_sdk.frameworks; [ Foundation AppKit Security SystemConfiguration ]);
}
