{
  description = "Cua Driver for macOS — unofficial Nix package and Home Manager module, auto-updated from upstream";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      # Upstream ships one universal (arm64 + x86_64) macOS artifact.
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      lib = nixpkgs.lib;
      forSystems = lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      overlays.default = final: _prev: {
        cua-driver = final.callPackage ./pkgs/cua-driver { };
      };

      packages = forSystems (
        system:
        let
          cua-driver = (pkgsFor system).callPackage ./pkgs/cua-driver { };
        in
        {
          inherit cua-driver;
          default = cua-driver;
        }
      );

      # Installs CuaDriver.app at a stable path so macOS privacy grants survive
      # upgrades, and puts the cua-driver CLI on PATH.
      homeManagerModules.default = import ./modules/home-manager.nix self;
      homeManagerModules.cua-driver = self.homeManagerModules.default;

      apps = forSystems (
        system:
        let
          pkg = self.packages.${system}.cua-driver;
        in
        {
          default = {
            type = "app";
            program = "${pkg}/bin/cua-driver";
            meta.description = "Run the cua-driver CLI";
          };
        }
      );

      checks = forSystems (system: {
        build = self.packages.${system}.cua-driver;
      });

      formatter = forSystems (system: (pkgsFor system).nixfmt);
    };
}
