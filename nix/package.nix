{ lib
, beam
, beamPackages ? beam.packagesWith beam.interpreters.erlang_27
, esbuild
, tailwindcss
, makeWrapper
}:

let
  pname = "tsundoku";
  version = "0.1.0";

  src = ../.;

  # Hex deps. The hash MUST be updated whenever mix.lock changes.
  # First build will fail with the expected hash; copy it in here.
  mixFodDeps = beamPackages.fetchMixDeps {
    pname = "${pname}-deps";
    inherit src version;
    hash = "sha256-xZg1Hs2sYUSkm2MaZM0VCpeJDIHV7RtwYAZLfi0Rc/c=";
  };
in
beamPackages.mixRelease {
  inherit pname version src mixFodDeps;

  removeCookie = false;

  nativeBuildInputs = [ esbuild tailwindcss makeWrapper ];

  # Tell the elixir esbuild/tailwind libraries to use the Nix-provided
  # binaries instead of downloading. Matches what flake.nix dev shell
  # exposes so dev and build behave the same.
  MIX_ESBUILD_PATH = "${esbuild}/bin/esbuild";
  MIX_ESBUILD_VERSION = esbuild.version;
  MIX_TAILWIND_PATH = "${tailwindcss}/bin/tailwindcss";
  MIX_TAILWIND_VERSION = tailwindcss.version;

  preBuild = ''
    # mixRelease runs from a copy of $src that has _build / .nix-mix
    # already wiped, so the assets.static alias is what populates
    # priv/static/{manifest.webmanifest, images/*} from assets/static.
    mix assets.deploy
  '';

  meta = with lib; {
    description = "Personal bookmarks server with LiveView, an extension, and Atom feeds";
    homepage = "https://github.com/crertel/tsundoku";
    # License intentionally omitted — the project hasn't declared one.
    # Add `license = licenses.X;` here when that changes.
    platforms = platforms.linux;
    mainProgram = pname;
  };
}
