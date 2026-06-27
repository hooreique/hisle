{
  fetchurl,
  lib,
  stdenvNoCC,
  undmg,
}:

let
  release = import ./build-info.nix;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "hisle";
  version = release.version;

  src = fetchurl {
    url =
      "https://github.com/hooreique/hisle/releases/download/v${finalAttrs.version}/"
      + "hisle-${finalAttrs.version}.dmg";
    hash = release.dmgHash;
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
