{
  fetchurl,
  lib,
  stdenvNoCC,
  undmg,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "hisle";
  version = "0.1.6";

  src = fetchurl {
    url =
      "https://github.com/hooreique/hisle/releases/download/v${finalAttrs.version}/"
      + "hisle-${finalAttrs.version}.dmg";
    hash = "sha256-UUY7qBoyEFPNZw/d+XZ6VO2k6yMX04qUAaNRc3PxHhA=";
  };

  nativeBuildInputs = [
    undmg
  ];

  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  unpackPhase = ''
    runHook preUnpack

    undmg "$src"

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    test -d hisle.app
    mkdir -p "$out/Applications"
    cp -R hisle.app "$out/Applications/"

    runHook postInstall
  '';

  meta = {
    description = "Hisle, a small Korean input method focused on personal preferences";
    homepage = "https://github.com/hooreique/hisle";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
