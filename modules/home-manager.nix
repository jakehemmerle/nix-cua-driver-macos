self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.cua-driver;
  pkg = cfg.package;

  appName = "CuaDriver.app";
  appPath = "${cfg.appDirectory}/${appName}";
  executable = "${appPath}/Contents/MacOS/cua-driver";
  teamIdentifier = pkg.passthru.teamIdentifier or "YCK386LBJ7";
  agentLabel = "org.nix-community.home.cua-driver";

  # Updates come from this flake's pin; the self-updater would otherwise replace
  # the managed app with whatever upstream release is newest.
  environment = {
    CUA_DRIVER_RS_UPDATE_CHECK = "false";
  }
  // lib.optionalAttrs (!cfg.telemetry) {
    CUA_DRIVER_RS_TELEMETRY_ENABLED = "false";
  };

  exports = lib.concatStrings (
    lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}\n") environment
  );

  # Run the installed bundle's executable, not the store copy: macOS keys
  # Accessibility and Screen Recording grants to the app at its stable path.
  cli = pkgs.writeShellScriptBin "cua-driver" ''
    ${exports}
    exec ${lib.escapeShellArg executable} "$@"
  '';
in
{
  options.programs.cua-driver = {
    enable = lib.mkEnableOption "Cua Driver, the background computer-use driver and MCP server";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.cua-driver;
      defaultText = lib.literalExpression "nix-cua-driver-macos.packages.\${system}.cua-driver";
      description = "The Cua Driver package whose CuaDriver.app is installed.";
    };

    appDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/Applications";
      description = ''
        Directory that receives a real copy of CuaDriver.app. Upstream's
        LaunchServices relaunch, `cua-driver permissions grant` and macOS
        privacy attribution all expect the app at /Applications/CuaDriver.app;
        a symlink into the Nix store is not enough.
      '';
    };

    telemetry = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to leave Cua Driver's default-on telemetry enabled.";
    };

    daemon.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run `cua-driver serve` as a LaunchAgent so one-shot `cua-driver call`
        commands have a daemon. MCP clients (`cua-driver mcp`) do not need it.
      '';
    };

    executable = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = executable;
      description = ''
        Absolute path of the installed bundle executable. Use it as an MCP
        client's command with arguments [ "mcp" ], together with `environment`.
      '';
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      default = environment;
      description = "Environment the managed CLI and LaunchAgent pass to Cua Driver.";
    };

    cli = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = cli;
      description = "Wrapper that runs the installed app's cua-driver with `environment`.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = pkgs.stdenv.hostPlatform.isDarwin;
            message = "programs.cua-driver (nix-cua-driver-macos) supports macOS only.";
          }
        ];

        home.packages = [ cli ];

        home.activation.installCuaDriverApp =
          lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ]
            ''
              cua_src=${lib.escapeShellArg "${pkg}/Applications/${appName}"}
              cua_dir=${lib.escapeShellArg cfg.appDirectory}
              cua_dest=${lib.escapeShellArg appPath}
              cua_new="$cua_dir/.${appName}.nix-new"
              cua_old="$cua_dir/.${appName}.nix-old"

              cua_same() {
                [ -d "$cua_dest" ] && [ ! -L "$cua_dest" ] \
                  && cmp -s "$cua_src/Contents/Info.plist" "$cua_dest/Contents/Info.plist" \
                  && cmp -s "$cua_src/Contents/MacOS/cua-driver" "$cua_dest/Contents/MacOS/cua-driver"
              }

              if cua_same; then
                verboseEcho "CuaDriver.app is current at $cua_dest"
              elif [ -n "''${DRY_RUN:-}" ]; then
                echo "Would install $cua_src at $cua_dest"
              else
                if [ ! -d "$cua_dir" ] || [ ! -w "$cua_dir" ]; then
                  errorEcho "Cannot install CuaDriver.app: $cua_dir is not a writable directory."
                  exit 1
                fi
                for stale in "$cua_new" "$cua_old"; do
                  if [ -e "$stale" ]; then
                    chmod -R u+w "$stale"
                    rm -rf "$stale"
                  fi
                done

                # ditto copies the bundle exactly as Apple's installer would; the
                # store copy is read-only, so make the staged copy removable.
                /usr/bin/ditto "$cua_src" "$cua_new"
                chmod -R u+w "$cua_new"

                # Never move a bundle into place that is not the notarized,
                # Cua-signed app: that would also void the stored privacy grants.
                if ! /usr/bin/codesign --verify --deep --strict "$cua_new"; then
                  errorEcho "Staged CuaDriver.app failed code-signature verification."
                  rm -rf "$cua_new"
                  exit 1
                fi
                cua_team=$(/usr/bin/codesign -dv --verbose=4 "$cua_new" 2>&1 | sed -n 's/^TeamIdentifier=//p')
                if [ "$cua_team" != ${lib.escapeShellArg teamIdentifier} ]; then
                  errorEcho "Staged CuaDriver.app is signed by team '$cua_team', expected ${teamIdentifier}."
                  rm -rf "$cua_new"
                  exit 1
                fi

                # Stop a daemon still serving the previous binary (no-op if none).
                if [ -x "$cua_dest/Contents/MacOS/cua-driver" ]; then
                  CUA_DRIVER_RS_UPDATE_CHECK=false CUA_DRIVER_RS_TELEMETRY_ENABLED=false \
                    "$cua_dest/Contents/MacOS/cua-driver" stop >/dev/null 2>&1 || true
                fi

                if [ -e "$cua_dest" ] || [ -L "$cua_dest" ]; then
                  mv "$cua_dest" "$cua_old"
                fi
                if mv "$cua_new" "$cua_dest"; then
                  if [ -e "$cua_old" ]; then
                    chmod -R u+w "$cua_old"
                    rm -rf "$cua_old"
                  fi
                else
                  [ -e "$cua_old" ] && mv "$cua_old" "$cua_dest"
                  errorEcho "Could not move CuaDriver.app into $cua_dest."
                  exit 1
                fi

                /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
                  -f "$cua_dest" >/dev/null 2>&1 || true
                echo "Installed CuaDriver.app ${pkg.version} at $cua_dest"

                ${lib.optionalString cfg.daemon.enable ''
                  if /bin/launchctl print "gui/$(id -u)/${agentLabel}" >/dev/null 2>&1; then
                    /bin/launchctl kickstart -k "gui/$(id -u)/${agentLabel}" || true
                  fi
                ''}
              fi

              ${lib.optionalString (!cfg.telemetry) ''
                # Persist the opt-out too: an app relaunched through LaunchServices
                # does not inherit this environment.
                if [ -z "''${DRY_RUN:-}" ] && [ -x "$cua_dest/Contents/MacOS/cua-driver" ]; then
                  if ! env -u CUA_DRIVER_RS_TELEMETRY_ENABLED CUA_DRIVER_RS_UPDATE_CHECK=false \
                      "$cua_dest/Contents/MacOS/cua-driver" telemetry status 2>/dev/null \
                      | grep -q '^Telemetry: disabled'; then
                    env -u CUA_DRIVER_RS_TELEMETRY_ENABLED CUA_DRIVER_RS_UPDATE_CHECK=false \
                      "$cua_dest/Contents/MacOS/cua-driver" telemetry disable >/dev/null 2>&1 \
                      || warnEcho "Could not persist Cua Driver telemetry opt-out."
                  fi
                fi
              ''}
            '';
      }

      (lib.mkIf cfg.daemon.enable {
        launchd.agents.cua-driver = {
          enable = true;
          config = {
            Label = agentLabel;
            ProgramArguments = [
              executable
              "serve"
            ];
            EnvironmentVariables = environment;
            RunAtLoad = true;
            KeepAlive = true;
            ProcessType = "Interactive";
            StandardOutPath = "${config.home.homeDirectory}/Library/Logs/cua-driver.log";
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/cua-driver.log";
          };
        };
      })
    ]
  );
}
