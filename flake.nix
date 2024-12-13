{
  description = "";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, flake-utils, ... }: 
  flake-utils.lib.eachDefaultSystem (system: {
    overlay = final: prev: { tmodloader-server = final.callPackage ./pkgs/default.nix {}; };
    overlays.default = self.overlay;
    nixosModules.default = import ./modules/tmodloader-server;
  });
}
