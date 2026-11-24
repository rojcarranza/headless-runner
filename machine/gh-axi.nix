# gh-axi is an npm/pnpm project with no flake, so the source comes from the
# `gh-axi` input in flake.nix (its tag is the version) and is built here.
# Bump: edit the tag in flake.nix, then `nix flake lock path:$PWD/machine`, then
# replace pnpmDeps `hash` with lib.fakeHash and copy the real one from the build error.
{ lib, stdenv, nodejs, pnpm, pnpmConfigHook, fetchPnpmDeps, src }:

stdenv.mkDerivation (finalAttrs: {
  pname = "gh-axi";
  version = (lib.importJSON "${src}/package.json").version;
  inherit src;

  nativeBuildInputs = [ nodejs pnpm pnpmConfigHook ];
  # Host node lets patchShebangs rewrite `#!/usr/bin/env node` to the store's node.
  buildInputs = [ nodejs ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    fetcherVersion = 5;
    hash = "sha256-XUPe/9iGjZtdX2HXoxGTDrSuBLVf6T/lfGENoEHU400=";
  };

  buildPhase = ''
    runHook preBuild
    pnpm build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/gh-axi $out/bin
    cp -r dist package.json $out/lib/gh-axi/
    # The repository's release-age policy needs registry metadata, which the sandbox lacks.
    pnpm prune --prod --ignore-scripts --offline --config.minimumReleaseAge=0 --config.minimumReleaseAgeStrict=false
    cp -r node_modules $out/lib/gh-axi/
    ln -s $out/lib/gh-axi/dist/bin/gh-axi.js $out/bin/gh-axi
    chmod +x $out/lib/gh-axi/dist/bin/gh-axi.js
    runHook postInstall
  '';

  meta = {
    description = "Agent-friendly wrapper around the gh CLI";
    homepage = "https://github.com/kunchenguid/gh-axi";
    license = lib.licenses.mit;
    mainProgram = "gh-axi";
  };
})
