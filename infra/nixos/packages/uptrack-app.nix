# Uptrack Phoenix Application Package
# Builds the Elixir release for deployment
{ pkgs, lib, beamPackages, ... }:

beamPackages.mixRelease {
  pname = "uptrack";
  version = "0.1.0";

  src = lib.cleanSource ../../../.;  # Root of uptrack repo

  # Mix environment
  mixEnv = "prod";

  # Dependencies needed for compilation
  nativeBuildInputs = with pkgs; [
    nodejs  # For assets
    git
  ];

  # Compile assets before building release
  preBuild = ''
    mix assets.deploy
  '';

  # Skip tests during build
  doCheck = false;

  meta = with lib; {
    description = "Uptrack - Multi-region uptime monitoring";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
