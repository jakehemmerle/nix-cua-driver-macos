{
  lib,
  stdenvNoCC,
  fetchurl,
}:

# Upstream's agent skill pack (SKILL.md plus its platform and workflow guides),
# from the same release as the app. source.json pins both, so the skill always
# describes the installed driver version.
let
  source = lib.importJSON ./source.json;
in
stdenvNoCC.mkDerivation {
  pname = "cua-driver-skills";
  version = source.version;

  src = fetchurl {
    inherit (source.skills) url;
    hash = source.skills.sha256;
  };

  sourceRoot = "cua-driver-rs-v${source.version}-skills";

  dontBuild = true;
  dontConfigure = true;
  # Keep upstream bytes as released.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/cua-driver/skills"
    cp -R . "$out/share/cua-driver/skills/cua-driver"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    skill="$out/share/cua-driver/skills/cua-driver/SKILL.md"
    grep -qx 'name: cua-driver' "$skill"
    grep -Eq '^version: ${lib.escapeRegex source.version}([^0-9.]|$)' "$skill"
    runHook postInstallCheck
  '';

  passthru.skillName = "cua-driver";

  meta = {
    description = "Cua Driver agent skill pack matching the packaged driver release";
    homepage = "https://github.com/trycua/cua";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
