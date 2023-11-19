# This is just a sample setup!
#
# It's very barebones and no hardening is applied. The runner
# can easily run out of storage because of the limited size
# of the QCOW2.

{ pkgs, lib, config, ... }:
let
  inherit (lib) types;
  cfg = config.arc-runner;

  # https://stackoverflow.com/a/48513046
  load-runner-env = pkgs.writeScript "load-runner-env" ''
    runner_info="/runner-info/runner-info.json"

    while read -rd $"" line
    do
      export "info_$line"
    done < <(${pkgs.jq}/bin/jq -r <"$runner_info" \
             'to_entries|map("\(.key)=\(.value)\u0000")[]')
  '';
in {
  options = {
    arc-runner = {
      enable = lib.mkEnableOption "action-runner-controller runner";
      mountTag = lib.mkOption {
        type = types.str;
        default = "runner-info";
      };
      package = lib.mkOption {
        type = types.package;
        default = pkgs.github-runner;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    fileSystems.runner-info = {
      device = cfg.mountTag;
      fsType = "virtiofs";
      mountPoint = "/runner-info";
    };

    users.users.arc-runner = {
      isSystemUser = true;
      group = "arc-runner";
    };

    users.groups.arc-runner = {};

    security.sudo.extraRules = [
      {
        users = [ "arc-runner" ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" "SETENV" ];
          }
        ];
      }
    ];

    systemd.services.arc-runner = {
      wantedBy = [ "multi-user.target" ];
      requires = [ "runner\\x2dinfo.mount" ];
      after = [ "network-online.target" ];

      path = with pkgs; [
        # nixos/modules/services/continuous-integration/github-runner/service.nix
        bashInteractive
        coreutils
        git
        gnutar
        gzip

        config.nix.package
      ];

      environment = {
        HOME = "/var/lib/arc-runner";
        RUNNER_ROOT = "/var/lib/arc-runner";
      };

      serviceConfig = {
        StateDirectory = "arc-runner";
        User = "arc-runner";

        ExecStartPre = pkgs.writeShellScript "configure-runner" ''
          set -euo pipefail

          cd "$STATE_DIRECTORY"

          . ${load-runner-env}

          if [[ -n "$info_jitconfig" ]]; then
            exit 0
          fi

          args=(
            --unattended
            --disableupdate
            --replace
            --name "$info_name"
            --url "$info_url"
            --token "$info_token"
            --runnergroup "$info_groups"
            --labels "$info_labels"
          )
          if [[ "$info_ephemeral" == "true" ]]; then
            args+=(--ephemeral)
          fi

          ${cfg.package}/bin/Runner.Listener configure "''${args[@]}"
        '';

        ExecStart = pkgs.writeShellScript "start-runner" ''
          set -euo pipefail

          . ${load-runner-env}

          if [[ -n "$info_jitconfig" ]]; then
            export ACTIONS_RUNNER_INPUT_JITCONFIG="$info_jitconfig"
          fi

          exec ${cfg.package}/bin/Runner.Listener run --startuptype service
        '';

        ExecStop = pkgs.writeShellScript "stop-runner" ''
          set -euo pipefail

          cd "$STATE_DIRECTORY"

          . ${load-runner-env}

          if [[ -n "$info_jitconfig" ]]; then
            exit 0
          fi

          ${cfg.package}/bin/Runner.Listener remove \
            --token "$info_token"
        '';

        ExecStopPost = pkgs.writeShellScript "post-stop-runner" ''
          if ! [[ -e "/etc/keep-runner" ]]; then
            /run/wrappers/bin/sudo poweroff
          fi
        '';
      };
    };
  };
}
