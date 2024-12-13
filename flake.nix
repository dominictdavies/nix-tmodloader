{
  description = "";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, ... }: 
  {
    overlay = final: prev: { tmodloader-server = final.callPackage ./pkgs/default.nix {}; };
    overlays.default = self.overlay;
    nixosModules.tmodloader = import ./modules/tmodloader-server;
  };
}
