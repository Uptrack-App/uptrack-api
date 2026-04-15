# Uptrack Phoenix Application Package
# Builds the Elixir release for deployment
{ pkgs, lib, beamPackages, self, ... }:

let
  src = self;  # Flake source = git repo root (where mix.exs lives)
in
beamPackages.mixRelease {
  pname = "uptrack";
  version = "0.1.0";

  inherit src;

  # Mix environment
  mixEnv = "prod";

  # Pre-fetch all Mix dependencies as a Fixed Output Derivation (FOD)
  # To update: change sha256 to lib.fakeSha256, build, get correct hash from error
  mixFodDeps = beamPackages.fetchMixDeps {
    pname = "uptrack-deps";
    version = "0.1.0";
    inherit src;
    sha256 = "sha256-Elnug/PnQn/IHwAb8vi6KWgqymn8pqNq8uKd4rsIM9o=";
  };

  # Dependencies needed for compilation
  nativeBuildInputs = with pkgs; [
    nodejs  # For assets
    git
  ];

  # Fix heroicons git dep: fetchMixDeps creates a minimal .git with only HEAD.
  # Mix's lock check runs `git rev-parse HEAD` which needs objects/ and refs/.
  # Since deps are already copied writably to $MIX_DEPS_PATH, we just add
  # the missing git structure.
  # Fix heroicons git dep: fetchMixDeps creates a minimal .git with only HEAD.
  # Mix.SCM.Git.lock_status checks both `git config remote.origin.url` and
  # `git rev-parse HEAD`. We need objects/, refs/, and a config with origin.
  postConfigure = ''
    heroicons_git="$MIX_DEPS_PATH/heroicons/.git"
    if [ -d "$heroicons_git" ] && [ ! -d "$heroicons_git/objects" ]; then
      mkdir -p "$heroicons_git/objects" "$heroicons_git/refs"
      cat > "$heroicons_git/config" << 'GITCFG'
[remote "origin"]
	url = https://github.com/tailwindlabs/heroicons.git
GITCFG
    fi
  '';

  # Note: mix assets.deploy is NOT used here because it triggers Mix's deps
  # lock check which fails on heroicons git dep. The API primarily serves JSON.
  # Assets for the admin LiveView UI can be deployed separately if needed.

  # Skip tests during build
  doCheck = false;

  meta = with lib; {
    description = "Uptrack - Multi-region uptime monitoring";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
