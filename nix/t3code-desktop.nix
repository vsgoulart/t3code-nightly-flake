{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  unzip,
  makeBinaryWrapper,
  makeWrapper,
  appimageTools,
  version,
  tag,
  source,
  platforms,
  # Extra tools placed on the desktop app's PATH (inherited by its bundled
  # server), e.g. [ git gh codex ]. Nothing is added by default.
  extraRuntimePackages ? [ ],
}:

let
  pname = "t3code-desktop";
  appName = "T3 Code (Nightly)";

  # Upstream's prebuilt desktop build: signed .app zip on macOS, AppImage on Linux.
  src = fetchurl { inherit (source) url hash; };

  # The Nix store is read-only, so the in-app updater can never succeed.
  wrapperArgs = [
    "--set"
    "T3CODE_DISABLE_AUTO_UPDATE"
    "true"
  ]
  ++ lib.optionals (extraRuntimePackages != [ ]) [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath extraRuntimePackages)
  ];

  passthru = { inherit tag; };

  meta = {
    description = "T3 Code nightly desktop app, packaged from upstream prebuilt binaries";
    homepage = "https://t3.codes";
    downloadPage = "https://github.com/pingdotgg/t3code/releases";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/${tag}";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    inherit platforms;
    mainProgram = pname;
  };

  darwin = stdenvNoCC.mkDerivation {
    inherit
      pname
      version
      src
      passthru
      meta
      ;

    nativeBuildInputs = [
      unzip
      makeBinaryWrapper
    ];

    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;
    # Leave upstream's signed bundle byte-for-byte intact.
    dontFixup = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/Applications" "$out/bin"
      cp -R "${appName}.app" "$out/Applications/"
      makeBinaryWrapper \
        "$out/Applications/${appName}.app/Contents/MacOS/${appName}" \
        "$out/bin/${pname}" \
        ${lib.escapeShellArgs wrapperArgs}

      runHook postInstall
    '';
  };

  linux =
    let
      extracted = appimageTools.extract { inherit pname version src; };
    in
    appimageTools.wrapType2 {
      inherit
        pname
        version
        src
        passthru
        meta
        ;

      # Used by the bundled t3-browser-secret helper.
      extraPkgs = pkgs: [ pkgs.libsecret ];

      extraInstallCommands = ''
        source "${makeWrapper}/nix-support/setup-hook"
        wrapProgram "$out/bin/${pname}" ${lib.escapeShellArgs wrapperArgs}

        install -Dm444 "${extracted}/t3code.desktop" "$out/share/applications/${pname}.desktop"
        sed -i 's|^Exec=.*|Exec=${pname} %U|' "$out/share/applications/${pname}.desktop"
        cp -R "${extracted}/usr/share/icons" "$out/share/icons"
      '';
    };
in
if stdenv.hostPlatform.isDarwin then darwin else linux
