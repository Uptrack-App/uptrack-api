# Uptrack Phoenix Application Package
# Builds the Elixir release for deployment
{ pkgs, lib, beamPackages, self, ... }:

let
  src = self;  # Flake source = git repo root (where mix.exs lives)

  # Pre-fetched AppSignal agent — placed into deps/appsignal/c_src/ below so
  # mix_helpers.exs skips the (sandbox-blocked) network download at compile time.
  appsignal-agent = pkgs.callPackage ./appsignal-agent.nix {};
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

  # NOTE: this runs BEFORE `mix deps.compile`, which is invoked inside
  # configurePhase (see nixpkgs mix-release.nix:181). postConfigure would fire
  # too late — AppSignal's install task runs during that deps.compile step.
  preConfigure = ''
    # Fix heroicons git dep: fetchMixDeps creates a minimal .git with only HEAD.
    # Mix.SCM.Git.lock_status checks both `git config remote.origin.url` and
    # `git rev-parse HEAD`. We need objects/, refs/, and a config with origin.
    heroicons_git="$MIX_DEPS_PATH/heroicons/.git"
    if [ -d "$heroicons_git" ] && [ ! -d "$heroicons_git/objects" ]; then
      mkdir -p "$heroicons_git/objects" "$heroicons_git/refs"
      cat > "$heroicons_git/config" << 'GITCFG'
[remote "origin"]
	url = https://github.com/tailwindlabs/heroicons.git
GITCFG
    fi

    # Seed AppSignal's c_src/ with the pre-fetched agent so compile skips the
    # HTTP download (blocked by the Nix sandbox). AppSignal's install task
    # detects these files via has_local_release_files? and uses them directly
    # (see deps/appsignal/mix_helpers.exs:112,423).
    appsignal_c_src="$MIX_DEPS_PATH/appsignal/c_src"
    if [ -d "$MIX_DEPS_PATH/appsignal" ]; then
      mkdir -p "$appsignal_c_src"
      install -m 0755 ${appsignal-agent}/appsignal-agent    "$appsignal_c_src/"
      install -m 0644 ${appsignal-agent}/appsignal.h        "$appsignal_c_src/"
      install -m 0644 ${appsignal-agent}/libappsignal.a     "$appsignal_c_src/"
      install -m 0644 ${appsignal-agent}/appsignal.version  "$appsignal_c_src/"
      echo "AppSignal seed: files placed in $appsignal_c_src"
      ls -la "$appsignal_c_src"
    else
      echo "AppSignal seed: WARNING — $MIX_DEPS_PATH/appsignal does not exist yet"
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
