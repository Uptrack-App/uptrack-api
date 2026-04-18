# AppSignal agent binary + static library for NixOS.
#
# AppSignal's Elixir package normally downloads this at `mix deps.compile` time
# from CloudFront, which fails inside the hermetic Nix build sandbox. Instead we
# fetch it here as a fixed-output derivation (network allowed, hash-locked) and
# the parent uptrack-app derivation seeds deps/appsignal/c_src/ with these files.
# mix_helpers.exs:has_local_release_files? then short-circuits the download path
# (see deps/appsignal/mix_helpers.exs:112).
#
# When bumping the appsignal hex package, update `version` and the checksums
# below to match deps/appsignal/agent.exs.
{ stdenv, fetchurl, autoPatchelfHook, lib }:

let
  version = "0.36.7";

  agents = {
    "x86_64-linux" = {
      filename = "appsignal-x86_64-linux-all-static.tar.gz";
      sha256 = "59fa4c2b31f5f728174a7df66e034281c8b00b590ad4a69905e0e8d9ff8f4887";
    };
    "aarch64-linux" = {
      filename = "appsignal-aarch64-linux-all-static.tar.gz";
      sha256 = "aa2ab16361ab3d2709f050d7f83b5ba4c82c6e67e2b50201422147d6c266e205";
    };
  };

  agent = agents.${stdenv.hostPlatform.system} or
    (throw "appsignal-agent: unsupported platform ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "appsignal-agent";
  inherit version;

  src = fetchurl {
    url = "https://d135dj0rjqvssy.cloudfront.net/${version}/${agent.filename}";
    inherit (agent) sha256;
  };

  # Tarball is flat (no top-level dir)
  sourceRoot = ".";
  unpackPhase = ''
    runHook preUnpack
    tar -xzf $src
    runHook postUnpack
  '';

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    install -m 0755 appsignal-agent $out/
    install -m 0644 appsignal.h     $out/
    install -m 0644 libappsignal.a  $out/
    echo "${version}" > $out/appsignal.version
    runHook postInstall
  '';

  meta = with lib; {
    description = "AppSignal monitoring agent binary + static library";
    homepage = "https://github.com/appsignal/appsignal-agent";
    license = licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
