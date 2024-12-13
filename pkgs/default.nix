{
  pkgs ? import <nixpkgs> {},
  stdenv ? pkgs.stdenv,
  lib ? pkgs.lib,
  fetchurl ? pkgs.fetchurl,
  dotnet-sdk_8 ? pkgs.dotnet-sdk_8
}:
let 
  version = "v2024.11.2.0";
  name = "tmodloader-${version}";
  url = "https://github.com/tModLoader/tModLoader/releases/download/${version}/tModLoader.zip";

in
stdenv.mkDerivation {
  inherit version name;

  nativeBuildInputs = with pkgs; [ unzip ];

  src = fetchurl {
    inherit url;
    sha256 = "sha256-l7ZxDFMmNyt9TVovAKqmo++to0zMaeXmkECoHtkpEGc=";
  };

  unpackPhase = "unzip $src";
  
  installPhase = ''
    mkdir -p $out/bin
    mv * $out

    cat > $out/bin/terraria-server << EOF
    #!/bin/sh 
    exec ${lib.getExe dotnet-sdk_8} $out/tModLoader.dll -server \$@
    EOF

    chmod +x $out/bin/terraria-server
  '';
}
