# Blackmatter macOS — Home-Manager module
#
# Provides Swift toolchain and macOS build helpers in the user environment.
# Darwin-only — no-ops on Linux.
{ lib, config, pkgs, ... }:

let
  cfg = config.blackmatter.components.macos;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
in
{
  options.blackmatter.components.macos = {
    enable = lib.mkEnableOption "blackmatter macOS native toolchain";

    swift = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install Swift 6 toolchain in user environment";
      };
    };
  };

  config = lib.mkIf (cfg.enable && isDarwin) (lib.mkMerge [
    # Swift toolchain — priority 100 so it yields to clang-wrapper (pri 10)
    # and clang-tools already in home.packages from other modules.
    (lib.mkIf cfg.swift.enable (let
      swiftPkg = pkgs.swiftToolchain or pkgs.swift;
    in {
      home.packages = [
        (swiftPkg // { meta = (swiftPkg.meta or {}) // { priority = 100; }; })
      ];
    }))
  ]);
}
