{
  description = "T3 Code nightly, packaged from upstream prebuilt binaries";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      # Pinned by scripts/update.sh; see README.md.
      sources = lib.importJSON ./sources.json;
      platforms = builtins.attrNames sources.cli;
      forAllSystems = lib.genAttrs platforms;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          common = {
            inherit (sources) version tag;
            inherit platforms;
          };
          t3code = pkgs.callPackage ./nix/t3code.nix (common // { source = sources.cli.${system}; });
          t3code-desktop = pkgs.callPackage ./nix/t3code-desktop.nix (
            common // { source = sources.desktop.${system}; }
          );
        in
        {
          inherit t3code t3code-desktop;
          default = t3code;
        }
      );

      apps = forAllSystems (
        system:
        let
          app = package: {
            type = "app";
            program = lib.getExe package;
            meta.description = package.meta.description;
          };
        in
        {
          default = app self.packages.${system}.t3code;
          desktop = app self.packages.${system}.t3code-desktop;
        }
      );
    };
}
