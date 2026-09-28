{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeBinaryWrapper,
  installShellFiles,
  versionCheckHook,
  version,
  tag,
  source,
  platforms,
  # Extra tools placed on the server's PATH, e.g. [ git gh codex ].
  # Nothing is added by default; the host PATH is used like upstream's installer.
  extraRuntimePackages ? [ ],
}:

let
  wrapperArgs = lib.optionals (extraRuntimePackages != [ ]) [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath extraRuntimePackages)
  ];
in
stdenv.mkDerivation {
  pname = "t3code";
  inherit version;

  # Upstream's prebuilt portable archive; nothing is compiled.
  src = fetchurl { inherit (source) url hash; };

  nativeBuildInputs = [
    makeBinaryWrapper
    installShellFiles
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  # libstdc++, libgcc_s and libatomic for the prebuilt ELF binaries.
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ (lib.getLib stdenv.cc.cc) ];

  # Upstream ships both glibc and musl builds of libfff_c.so; only glibc is loaded.
  autoPatchelfIgnoreMissingDeps = [ "libc.musl-*.so.1" ];
  # Patched explicitly in postInstall so completions can be generated afterwards.
  dontAutoPatchelf = true;

  dontConfigure = true;
  dontBuild = true;
  # `t3` is a Node.js single executable application: stripping could drop the
  # embedded app, and on Darwin would invalidate upstream's code signature.
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/libexec/t3code" "$out/bin"
    cp -R . "$out/libexec/t3code/"

    runHook postInstall
  '';

  postInstall = ''
    ${lib.optionalString stdenv.hostPlatform.isLinux ''autoPatchelf "$out/libexec"''}

    monitor=("$out"/libexec/t3code/resource-monitor/*/t3-resource-monitor)
    if [[ ''${#monitor[@]} -ne 1 || ! -x "''${monitor[0]}" ]]; then
      echo "Expected exactly one bundled t3-resource-monitor" >&2
      exit 1
    fi

    makeBinaryWrapper "$out/libexec/t3code/t3" "$out/bin/t3" \
      --set-default T3CODE_RESOURCE_MONITOR_PATH "''${monitor[0]}" \
      ${lib.escapeShellArgs wrapperArgs}
  ''
  + lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    export HOME="$(mktemp -d)"
    installShellCompletion --cmd t3 \
      --bash <("$out/bin/t3" --completions bash) \
      --fish <("$out/bin/t3" --completions fish) \
      --zsh <("$out/bin/t3" --completions zsh)
  '';

  # Fails if the embedded application was lost (plain Node would print its own version).
  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "--version";

  passthru = { inherit tag; };

  meta = {
    description = "T3 Code nightly server and CLI, packaged from upstream prebuilt binaries";
    homepage = "https://t3.codes";
    downloadPage = "https://github.com/pingdotgg/t3code/releases";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/${tag}";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    inherit platforms;
    mainProgram = "t3";
  };
}
