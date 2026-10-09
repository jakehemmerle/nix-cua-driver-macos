{
  lib,
  stdenvNoCC,
  fetchurl,
}:

# Cua Driver — repackaged from the signed, notarized darwin-universal release
# tarball. `source.json` is regenerated from upstream by scripts/update.sh, so
# this file never needs hand-editing on a version bump.
let
  source = lib.importJSON ./source.json;
in
stdenvNoCC.mkDerivation {
  pname = "cua-driver";
  version = source.version;

  src = fetchurl {
    inherit (source) url;
    hash = source.sha256;
  };

  sourceRoot = "cua-driver-rs-${source.version}-darwin-universal";

  # CuaDriver.app is Developer ID-signed and notarized. Nix's fixup phase would
  # strip / re-sign the Mach-O binaries and break that signature (and with it
  # Gatekeeper and the macOS privacy grants). Leave the bytes untouched.
  dontFixup = true;
  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications" "$out/bin" "$out/lib" "$out/include" "$out/share/doc/cua-driver"
    cp -R CuaDriver.app "$out/Applications/CuaDriver.app"

    # The CLI is the bundle's own executable: macOS attributes permissions to
    # the app it runs from. For stable grants across upgrades, install the app
    # at a fixed path (see modules/home-manager.nix) and run it from there.
    ln -s "$out/Applications/CuaDriver.app/Contents/MacOS/cua-driver" "$out/bin/cua-driver"
    ln -s "$out/Applications/CuaDriver.app/Contents/MacOS/cua-cursor-theme" "$out/bin/cua-cursor-theme"

    # Embeddable SDK pieces shipped alongside the app.
    cp libcua_driver_sdk.dylib cua_driver_node_runtime.node "$out/lib/"
    cp cua_driver_abi.h "$out/include/"
    cp LICENSE THIRD_PARTY_NOTICES.md "$out/share/doc/cua-driver/"

    runHook postInstall
  '';

  # Smoke-test the unpacked copy, never $out: executing a signed bundle marks
  # it with a protected file flag that Nix then cannot clear from the output.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    CUA_DRIVER_RS_TELEMETRY_ENABLED=false CUA_DRIVER_RS_UPDATE_CHECK=false \
      ./CuaDriver.app/Contents/MacOS/cua-driver --version | grep -F "${source.version}"
    runHook postCheck
  '';

  passthru = {
    appName = "CuaDriver.app";
    bundleIdentifier = "com.trycua.driver";
    teamIdentifier = "YCK386LBJ7";
  };

  meta = {
    description = "Background computer-use driver and MCP server for AI agents (macOS)";
    homepage = "https://cua.ai/cua-driver";
    changelog = "https://github.com/trycua/cua/releases/tag/cua-driver-rs-v${source.version}";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    mainProgram = "cua-driver";
  };
}
