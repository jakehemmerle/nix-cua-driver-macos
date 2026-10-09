# nix-cua-driver-macos

Unofficial [Nix](https://nixos.org) flake for **[Cua Driver](https://cua.ai/cua-driver)** on macOS: the background computer-use driver and MCP server from [trycua/cua](https://github.com/trycua/cua). It repackages the official signed and notarized `darwin-universal` release and keeps it current automatically.

> **Platform:** `aarch64-darwin`, `x86_64-darwin` (one universal artifact). For Linux, use upstream's own flake (`github:trycua/cua#cua-driver`).
> **Unofficial:** not affiliated with Cua AI, Inc. The release tarball is fetched, checked against its hash, and installed byte-for-byte unmodified.

## Why a module, not just a package

macOS ties Accessibility and Screen Recording grants to the signed app at a stable path. Upstream's `cua-driver mcp` relaunches itself through LaunchServices and `cua-driver permissions grant` expect `/Applications/CuaDriver.app`. A symlink into the Nix store changes path on every bump and loses those grants. The Home Manager module therefore copies the untouched bundle into `/Applications`, after checking its code signature and Cua's Team ID (`YCK386LBJ7`). It replaces the copy only when the pinned version changes. It also:

- puts a `cua-driver` wrapper on `PATH` that runs the installed bundle;
- disables the built-in self-updater (`CUA_DRIVER_RS_UPDATE_CHECK=false`), because this flake owns updates;
- opts out of upstream's default-on telemetry, both through the environment and persistently, unless `telemetry = true`;
- optionally runs `cua-driver serve` as a LaunchAgent (`daemon.enable`).

## Use it with Home Manager

```nix
# flake.nix
inputs.nix-cua-driver-macos = {
  url = "github:jakehemmerle/nix-cua-driver-macos";
  inputs.nixpkgs.follows = "nixpkgs";
};

# Home Manager module (receives your flake inputs)
{ inputs, config, ... }:
{
  imports = [ inputs.nix-cua-driver-macos.homeManagerModules.default ];
  programs.cua-driver.enable = true;
}
```

After the first activation, grant permissions once with `cua-driver permissions grant`, then check them with `cua-driver permissions status`.

### MCP clients

Point a stdio MCP client at the installed bundle:

```nix
command = config.programs.cua-driver.executable;   # /Applications/CuaDriver.app/Contents/MacOS/cua-driver
args = [ "mcp" ];
env = config.programs.cua-driver.environment;
```

### Options

| Option | Default | Meaning |
|---|---|---|
| `enable` | `false` | Install CuaDriver.app and the CLI |
| `package` | this flake's `cua-driver` | Package to install |
| `appDirectory` | `/Applications` | Where the real app copy lives (must be writable by the user) |
| `telemetry` | `false` | Leave upstream telemetry on |
| `daemon.enable` | `false` | Run `cua-driver serve` as a LaunchAgent |
| `executable`, `environment`, `cli` | read-only | For wiring MCP clients |

## Package only

```sh
nix run github:jakehemmerle/nix-cua-driver-macos -- --version
nix build github:jakehemmerle/nix-cua-driver-macos   # result/Applications/CuaDriver.app, result/bin/cua-driver
```

Running the CLI straight from the store works for read-only commands. For desktop control, use the module (or copy the app to `/Applications`) so permissions stay attached to a stable app.

## Auto-update

Every 12 hours, `.github/workflows/update.yml` reads Homebrew's `cuadriver` cask through its JSON API. It requires the URL to be trycua/cua's own `darwin-universal` release asset and writes `pkgs/cua-driver/source.json`. It then builds the package, verifies the notarization and Team ID, smoke-tests the CLI, and commits the bump to `main`. To update by hand:

```sh
./scripts/update.sh && nix build .#cua-driver && ./scripts/verify-signature.sh result
```

GitHub disables scheduled workflows in public repos after 60 days without activity. When upstream has been quiet for 45 days, the workflow pushes an empty keep-alive commit.

## License

The packaging code is MIT ([`LICENSE`](LICENSE)). Cua Driver is MIT-licensed by Cua AI, Inc.; see the upstream repository.
