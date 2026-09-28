# T3 Code Nightly Flake

A Nix flake providing the latest nightly build of
[T3 Code](https://github.com/pingdotgg/t3code).

It repackages upstream's prebuilt nightly release assets; nothing is built
from source. For the stable, source-built package, use `t3code` from nixpkgs.

| Package          | Contents                                             | Upstream asset                      |
| ---------------- | ---------------------------------------------------- | ----------------------------------- |
| `t3code`         | `t3` server and CLI (default)                        | `t3-<version>-<platform>.tar.gz`    |
| `t3code-desktop` | Electron desktop app, launched with `t3code-desktop` | `.app` zip (macOS), AppImage (Linux) |

Supported systems: `aarch64-darwin` (Apple Silicon), `x86_64-linux` and
`aarch64-linux`. Upstream publishes no `t3` binary for Intel Macs.

## Run

```console
nix run github:vsgoulart/t3code-nightly-flake
nix run github:vsgoulart/t3code-nightly-flake#desktop
```

## Install

```console
nix profile install github:vsgoulart/t3code-nightly-flake
nix profile install github:vsgoulart/t3code-nightly-flake#t3code-desktop
```

T3 Code drives coding agents installed on the machine. Install and authenticate
at least one provider CLI (Codex, Claude Code, Cursor, OpenCode, ...) and make
sure it is on the `PATH` T3 Code sees.

## Adding tools to `PATH`

Nothing is added to `PATH` by default. To bundle tools with the wrapper, override
`extraRuntimePackages` (both packages accept it):

```nix
t3code-nightly.packages.${system}.t3code.override {
  extraRuntimePackages = with pkgs; [ git gh codex ];
}
```

## Differences from upstream installs

- **Self-update is disabled.** The Nix store is read-only, so `t3 update` and
  the desktop app's updater cannot work. The desktop launcher sets
  `T3CODE_DISABLE_AUTO_UPDATE=true`. Update through this flake instead, for
  example with `nix profile upgrade`.
- **macOS app launched from Finder.** The variable above only applies when the
  app is started with `t3code-desktop`; changing the signed bundle to embed it
  would break its signature. To also cover Finder, Dock and Spotlight launches:

  ```console
  launchctl setenv T3CODE_DISABLE_AUTO_UPDATE true
  ```

- **Background service.** `t3 service install` records the path of the running
  binary, which is a Nix store path. It stops working once that path is
  garbage-collected, so reinstall the service after upgrading.

## Updates

The update workflow runs every six hours (and on manual dispatch). It:

1. Selects the newest release tagged `v*-nightly.*`, ignoring preview and
   stable releases, whose six required assets are fully uploaded. A nightly
   that is still uploading is skipped until the next run.
2. Pins each asset's SHA-256 in `sources.json`, taken from GitHub's asset
   digest and cross-checked against upstream's `SHA256SUMS`.
3. Builds both packages natively on x86_64 Linux, ARM64 Linux and Apple
   Silicon, checks that `t3 --version` reports the pinned version, and
   verifies the macOS code signatures.
4. Commits `sources.json` only when every platform passes.

To update a local checkout manually:

```console
bash scripts/update.sh
nix build .#t3code .#t3code-desktop
```

Set `T3CODE_NIGHTLY_TAG=v<version>` to pin a specific nightly.
