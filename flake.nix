{
  description = "";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { ... }: 
  {
    overlays.default = final: prev: { tmodloader-server = final.callPackage ./pkgs/default.nix {}; };
    nixosModules.default = import ./modules;
  };
}
