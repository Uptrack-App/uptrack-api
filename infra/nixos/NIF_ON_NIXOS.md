# Native Extensions (NIFs) on NixOS — Lessons Learned

Operational notes from debugging AppSignal's NIF on our NixOS deployment.
Keep this as a reference when adding any Elixir/Erlang dep that builds a C/Rust
NIF or downloads a prebuilt agent binary (AppSignal, Rustler-based libs, etc.).

## Symptoms to recognize

The app boots but the NIF silently no-ops. Typical signs:

- Boot log shows `Failed to load NIF library: '.../priv/<name>.so: cannot open
  shared object file: No such file or directory'`.
- Or: `Could not download archive from any of our mirrors` during `mix compile`.
- Or (subtler): no error at all, but the subprocess/sidecar that the NIF should
  spawn never appears in `pgrep`, and the vendor's dashboard is empty.
- The dependency's own `priv/install.report` (if it writes one) will say
  `"source":"remote"` with a failed download, or reference a `darwin`/unrelated
  target instead of the deploy target.

## Three compounding root causes

### 1. Mix downloads a prebuilt binary at compile time
Many libs (AppSignal, some Rustler crates, etc.) fetch an arch-specific tarball
from the vendor CDN during `mix deps.compile`. In AppSignal's case this happens
in `deps/appsignal/mix_helpers.exs:install/0` via `Finch.request`.

### 2. Nix build sandbox has no network
`beamPackages.mixRelease` + `fetchMixDeps` pre-fetches Hex packages as a
Fixed-Output Derivation (network allowed there, hash-pinned). But `mix
deps.compile` runs inside the hermetic sandbox with no network — the vendor
download fails with `:nxdomain`. The compile silently produces no `.so`.

### 3. Prebuilt binaries don't run on NixOS unmodified
Even if you managed to download the binary, it's linked against
`/lib64/ld-linux-x86-64.so.2` which doesn't exist on NixOS. Needs
`autoPatchelfHook` to rewrite the ELF interpreter/RPATH to Nix store paths.

## The pattern that works

Three pieces:

### Piece A — Fetch the binary as its own FOD derivation
See `infra/nixos/modules/packages/appsignal-agent.nix` for the template.
Key points:
- `fetchurl` with `sha256` = the vendor's published checksum (network allowed
  at fetch stage, hash pinned for reproducibility).
- `nativeBuildInputs = [ autoPatchelfHook ]`, `buildInputs = [ stdenv.cc.cc.lib
  ]` — this rewrites the ELF so the binary can execute on NixOS.
- Expose per-arch entries so `x86_64-linux` and `aarch64-linux` both work.
- **Pin the version to match the hex package's expectations.** AppSignal's
  version lives at `deps/appsignal/agent.exs:7`. Bumping the hex package is a
  two-step: update that file + update `version`/`sha256` in the Nix derivation.

### Piece B — Seed files where the hex package looks locally
Most libs that download at compile time have an undocumented "local files"
escape hatch. AppSignal's is at `deps/appsignal/mix_helpers.exs:112`:

```elixir
has_local_release_files?() ->
  Mix.shell().info("AppSignal: Using local agent release.")
  # copies from c_src/ to priv/, skips download
```

It checks for `{appsignal-agent, appsignal.h, libappsignal.a}` in
`deps/appsignal/c_src/`. Drop the files there and the download step is skipped.

Before adopting this pattern for a new lib, **read the hex package's source**
to confirm it has an equivalent check and what files/paths it expects. If it
doesn't, you may need to patch `mix_helpers.exs` (or equivalent) as part of a
`postPatch` step.

### Piece C — Seed in `preConfigure`, not `postConfigure`
This is the gotcha that cost us a deploy. Nixpkgs `pkgs/development/beam-modules/mix-release.nix:172-204`:

```nix
configurePhase = ''
  runHook preConfigure
  mix deps.compile --no-deps-check --skip-umbrella-children  # ← vendor download fires HERE
  # ...symlink deps...
  runHook postConfigure                                       # ← too late
'';
```

`mix deps.compile` runs **inside** `configurePhase`, before `postConfigure`.
Files seeded in `postConfigure` arrive after the vendor download has already
failed. **Use `preConfigure`** — by that point `$MIX_DEPS_PATH` is populated
(copied from the FOD in `postUnpack`) and writable.

See `infra/nixos/modules/packages/uptrack-app.nix` for the wiring.

## How to verify it worked

Four signals, ordered from cheapest to most definitive:

1. **Build log** — the vendor's "using local files" message should appear.
   For AppSignal: `AppSignal: Using local agent release.` in the colmena build
   output. If you see `Could not download archive from any of our mirrors`
   instead, seeding missed or ran too late.

2. **Release filesystem** — after deploy:
   ```bash
   ssh <node> 'ls /nix/store/*-uptrack-*/lib/<dep>-*/priv/'
   ```
   Should show both the `.so` and the sidecar binary (e.g. `appsignal_extension.so`,
   `appsignal-agent`).

3. **Runtime — process list** — sidecar subprocess alive:
   ```bash
   ssh <node> 'pgrep -af <agent-name>'
   ```
   e.g. `appsignal-agent start --private`. If the NIF failed to load, the
   subprocess is never spawned even though `systemctl is-active uptrack` says
   `active`.

4. **Vendor dashboard** — the node appears as a host with live metrics.
   Usually takes 30–90s after boot.

If signals 1–3 pass but 4 is empty, the issue is upstream (API key, config),
not the Nix packaging.

## Checklist for adding a new native-dep hex package

- [ ] Identify whether the package downloads anything at compile time. Grep its
      `mix.exs` + `mix_helpers.exs` for `Finch`, `HTTPoison`, `:httpc`,
      `System.cmd("curl", ...)`, `Req`, `fetch`, `download`.
- [ ] Find the vendor's published binary checksums file (e.g. `agent.exs`).
      Confirm it covers `x86_64-linux` and `aarch64-linux`.
- [ ] Find its "local files" escape hatch. If none, plan to patch the helper.
- [ ] Write the binary-as-FOD derivation with `autoPatchelfHook`.
- [ ] Seed the expected path in `preConfigure` of the `mixRelease`. Add a log
      echo so failures are loud.
- [ ] Verify all four signals above on a single node before rolling to the rest.

## Gotchas collected along the way

- `runtime.exs` reads `PORT`, not `PHX_PORT`. If you change ports in the
  systemd service, export both — otherwise the app binds the default 4000 and
  collides with whatever you put in front.
- `$MIX_DEPS_PATH` resolves to `$TEMPDIR/deps` (observed `/build/deps` in the
  sandbox). Relative `deps/` works once the symlink exists, but that symlink is
  only created **after** `mix deps.compile`. Write through `$MIX_DEPS_PATH`.
- `fetchMixDeps.sha256` covers only the hex source. It does NOT cover anything
  downloaded during `mix deps.compile`. That's why the vendor download has to
  be replaced, not re-hashed.
- Vendor tarballs that are flat at the archive root need `sourceRoot = "."`
  in the derivation.
- Bumping the hex package silently bumps the expected agent version. Both the
  hex package and the agent FOD derivation must be updated together; mismatched
  pairs either fail to load or mis-report.
