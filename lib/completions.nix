# ============================================================================
# COMPLETIONS - Shell completion generation for Swift ArgumentParser tools
# ============================================================================
# Swift's ArgumentParser supports `--generate-completion-script {bash,zsh,fish}`.
# This helper generates nativeBuildInputs and a postInstall script snippet
# for installing completions into the Nix store.
#
# Follows substrate's completions.nix pattern but uses Swift's completion API.
#
# Internal helper — used by mkSwiftPackage and mkSwiftToolRelease.
#
# Usage:
#   completionAttrs = (import ./completions.nix).mkSwiftCompletionAttrs pkgs {
#     pname = "my-tool";
#     completions = { install = true; };
#   };
#   # Returns: { nativeBuildInputs = [...]; postInstallScript = "..."; }
{
  # Generate nativeBuildInputs and postInstall script for Swift shell completions.
  #
  # completions: null or { install = true; command ? pname; }
  # pname: package name (fallback for command name)
  mkSwiftCompletionAttrs = pkgs: {
    pname,
    completions ? null,
  }: let
    lib = pkgs.lib;
    needsInstallShellFiles = completions != null && (completions.install or false);
    cmd = if completions != null then (completions.command or pname) else pname;
  in {
    nativeBuildInputs = lib.optional needsInstallShellFiles pkgs.installShellFiles;

    postInstallScript =
      if completions == null || !(completions.install or false) then ""
      else ''
        installShellCompletion --cmd ${cmd} \
          --bash <($out/bin/${cmd} --generate-completion-script bash) \
          --zsh <($out/bin/${cmd} --generate-completion-script zsh) \
          --fish <($out/bin/${cmd} --generate-completion-script fish)
      '';
  };
}
