{ pkgs, stdenv, lib, fetchurl, dotnet-sdk_8 }:
let 
  version = "v2025.05.3.0";
  name = "tmodloader-${version}";
  url = "https://github.com/tModLoader/tModLoader/releases/download/${version}/tModLoader.zip";

in
stdenv.mkDerivation {
  inherit version name;

  nativeBuildInputs = with pkgs; [ unzip ];

  src = fetchurl {
    inherit url;
    sha256 = "sha256-EW8FF1zf3L6s0VX9v27eVi+hJ/wWphyYIw8gQEPfH4Y=";
  };

  unpackPhase = "unzip $src";
  
  installPhase = ''
    mkdir -p $out/bin
    mv * $out

    cat > $out/bin/tmodloader-server << EOF
    #!/bin/sh 
    cd $out
    exec ${lib.getExe dotnet-sdk_8} $out/tModLoader.dll -server \$@
    EOF

    chmod +x $out/bin/tmodloader-server

    # make a place for logging
    ln -s /tmp $out/tModLoader-Logs 
  '';

  meta = with lib; {
    homepage = "https://www.tmodloader.net";
    description = "Dedicated server for tModLoader, a modded version of Terraria";
    platforms = [ "x86_64-linux" ];
    license = licenses.mit;
    mainProgram = "tmodloader-server";
  };
}
