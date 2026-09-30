{
  lib,
  stdenv,
  beamPackages,
  fetchurl,
  makeWrapper,
  patchelf,
  ffmpeg-headless,
  tailwindcss_4,
  esbuild,
}: let
  pname = "pup_watch";
  version = "0.1.0";
  src = lib.cleanSourceWith {
    src = ../.;
    filter = path: _: let
      rel = lib.removePrefix (toString ../. + "/") (toString path);
    in
      !(lib.any (p: lib.hasPrefix p rel) ["_build" "deps" ".devenv" ".nix-" "tmp" "priv/static/assets" "pupwatch_"]);
  };

  mixFodDeps = beamPackages.fetchMixDeps {
    pname = "mix-deps-${pname}";
    inherit src version;
    hash = "sha256-BD1CqJUnpiIjo57XcAN7XZ+8oTj1rxf+fW87NkKDvFM=";
  };

  # evision's own build would download this; the sandbox can't.
  evisionNif = fetchurl {
    url = "https://github.com/cocoa-xu/evision/releases/download/v0.2.17/evision-nif_2.16-x86_64-linux-gnu-contrib-0.2.17.tar.gz";
    hash = "sha256-fgwZQnwq7nicLsr3oQ+jXKyKUzZHg01mtVmQi6tZDa4=";
  };

  model = fetchurl {
    url = "https://github.com/Megvii-BaseDetection/YOLOX/releases/download/0.1.1rc0/yolox_s.onnx";
    sha256 = "c5c2d13e59ae883e6af3b45daea64af4833a4951c92d116ec270d9ddbe998063";
  };
in
  beamPackages.mixRelease {
    inherit pname version src mixFodDeps;

    nativeBuildInputs = [makeWrapper patchelf];

    MIX_TAILWIND_PATH = lib.getExe tailwindcss_4;
    MIX_ESBUILD_PATH = lib.getExe esbuild;

    preConfigure = ''
      export XDG_CACHE_HOME=$TMPDIR/cache
      mkdir -p $XDG_CACHE_HOME
      cp ${evisionNif} $XDG_CACHE_HOME/${evisionNif.name}
      mkdir -p priv/models
      cp ${model} priv/models/yolox_s.onnx
    '';

    postBuild = ''
      mix do deps.loadpaths --no-deps-check, assets.deploy
    '';

    # the precompiled NIF only finds libstdc++ because the BEAM happens to load it first
    postInstall = ''
      for f in $out/lib/evision-*/priv/evision.so $out/lib/evision-*/priv/lib/*.so.*.*.*; do
        patchelf --add-rpath ${lib.makeLibraryPath [stdenv.cc.cc.lib]} "$f"
      done
      wrapProgram $out/bin/pup_watch --prefix PATH : ${lib.makeBinPath [ffmpeg-headless]}
    '';

    meta.mainProgram = "pup_watch";
  }
