# Codesign Helpers — ad-hoc signing, entitlements, batch signing
#
# Extends the existing codesign pattern from nix/modules/shared/nix-performance.nix
# and dev-tools/nix-codesign. Provides composable shell snippets for use in
# derivation postFixup phases.
{ lib }:

{
  # Ad-hoc sign a single path.
  # Returns: shell snippet
  adHocSign = {
    path,
    deep ? false,
    entitlements ? null,
  }: ''
    /usr/bin/codesign -s - -f \
      ${lib.optionalString deep "--deep"} \
      ${lib.optionalString (entitlements != null) "--entitlements \"${entitlements}\""} \
      "${path}" 2>/dev/null || true
  '';

  # Generate an entitlements plist XML string from option attrs.
  # Returns: string (XML plist content)
  mkEntitlements = {
    allowJit ? false,
    disableLibraryValidation ? false,
    appSandbox ? false,
    networkClient ? false,
    networkServer ? false,
    fileReadAccess ? false,
    fileWriteAccess ? false,
  }: let
    boolEntry = key: value:
      lib.optionalString value ''
        <key>${key}</key>
        <true/>
      '';
  in ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      ${boolEntry "com.apple.security.cs.allow-jit" allowJit}
      ${boolEntry "com.apple.security.cs.disable-library-validation" disableLibraryValidation}
      ${boolEntry "com.apple.security.app-sandbox" appSandbox}
      ${boolEntry "com.apple.security.network.client" networkClient}
      ${boolEntry "com.apple.security.network.server" networkServer}
      ${boolEntry "com.apple.security.files.user-selected.read-only" fileReadAccess}
      ${boolEntry "com.apple.security.files.user-selected.read-write" fileWriteAccess}
    </dict>
    </plist>
  '';

  # Batch sign all Mach-O files in a directory tree.
  # Matches the pattern from nix-performance.nix post-build hook.
  # Returns: shell snippet
  signAllMachO = {
    path,
    entitlements ? null,
  }: ''
    _codesign_mach_o() {
      local f="$1"
      if /usr/bin/file "$f" 2>/dev/null | grep -q "Mach-O"; then
        chmod u+w "$f" 2>/dev/null || true
        /usr/bin/codesign -s - -f \
          ${lib.optionalString (entitlements != null) "--entitlements \"$entFile\""} \
          "$f" 2>/dev/null || true
        chmod u-w "$f" 2>/dev/null || true
      fi
    }
    find "${path}" -type f 2>/dev/null | while read -r f; do
      _codesign_mach_o "$f"
    done
  '';
}
