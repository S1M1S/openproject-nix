{ lib, config, pkgs, ... }: with lib; let
  pgVersion = lib.head (lib.splitString "." config.services.postgresql.package.version);
  cfg = config.services.openproject;
in {
  options.services.openproject = with types; {
    enable = mkEnableOption "openproject server";
    host = {
      name = mkOption {
        type = str;
        default = config.networking.hostName;
      };
      rootPath = mkOption {
        type = str;
        default = "";
      };
      bind.addr = mkOption {
        type = str;
        default = "0.0.0.0";
      };
      bind.port = mkOption {
        type = int;
        default= 6346;
      };
    };
    package = mkPackageOption pkgs "openproject" { };
    secrets.keyBaseFile = mkOption {
      type = str;
    };
    secrets.extraSeedEnvironmentFile = mkOption {
      type = str;
    };
    environment = mkOption {
      type = attrsOf str;
      default = {};
    };
    useJemalloc = mkOption {
      type = bool;
      default = true;
    };
    dbUrl = mkOption {
      type = str;
      default = "postgres:///openproject?host=/run/postgresql&username=openproject&pool=20&encoding=unicode&reconnect=true";
    };
    statePath = mkOption {
      type = str;
      default = "/var/lib/openproject";
    };
    imap = {
      enable = mkEnableOption "interact with openproject via mail";
    };
  };
  config = mkIf cfg.enable {

    nixpkgs.overlays = [
      (import ./overlay.nix { openprojectStatePath = cfg.statePath; })
    ];

    services.openproject = {
      ## see https://www.openproject.org/docs/installation-and-operations/configuration/environment/
      environment = {
        OPENPROJECT_HOST__NAME = cfg.host.name;
        OPENPROJECT_HSTS = "false";
        OPENPROJECT_RAILS_CACHE_STORE = "memcache";
        ## FIXME run multiple memcached instances instead
        ## FIXME or switch to redis if feasible
        OPENPROJECT_CACHE__MEMCACHE__SERVER = "unix:///run/memcached/memcached.sock";
        OPENPROJECT_CACHE__NAMESPACE = "openproject";
        OPENPROJECT_RAILS__RELATIVE__URL__ROOT = cfg.host.rootPath;
        RAILS_ENV="production";
        RAILS_MIN_THREADS = "4";
        RAILS_MAX_THREADS = "16";
        BUNDLE_WITHOUT = "development:test";
        # set to true to enable the email receiving feature. See ./docker/cron for more options;
        IMAP_ENABLED = "false";
        PGVERSION = pgVersion;
        CURRENT_PGVERSION = pgVersion;
        NEXT_PGVERSION = pgVersion;
        DATABASE_URL = cfg.dbUrl;
        SECRET_KEY_BASE_FILE = cfg.secrets.keyBaseFile;
        LD_PRELOAD = mkIf cfg.useJemalloc "${pkgs.jemalloc}/lib/libjemalloc.so";
      };
    };

    users = {
      groups.openproject = {};
      users.openproject = {
        isSystemUser = true;
        group = "openproject";
      };
    };

    launchd.daemons = {
      openproject-seeder = {
        serviceConfig = {
          ProgramArguments = [ "${cfg.package}/bin/openproject-seeder" "openproject" ];
          UserName = "openproject";
          KeepAlive = false;
          RunAtLoad = true;
          EnvironmentVariables = cfg.environment;
          StandardOutPath = "/var/log/openproject-seeder.log";
          StandardErrorPath = "/var/log/openproject-seeder.error.log";
        };
      };
      
      openproject-web = {
        serviceConfig = {
          ProgramArguments = [ "${cfg.package}/bin/openproject-web" "-b" cfg.host.bind.addr "-p" (toString cfg.host.bind.port) ];
          UserName = "openproject";
          KeepAlive = true;
          RunAtLoad = true;
          EnvironmentVariables = cfg.environment;
          StandardOutPath = "/var/log/openproject-web.log";
          StandardErrorPath = "/var/log/openproject-web.error.log";
        };
      };

      openproject-worker = {
        serviceConfig = {
          ProgramArguments = [ "${cfg.package}/bin/openproject-worker" ];
          UserName = "openproject";
          KeepAlive = true;
          RunAtLoad = true;
          EnvironmentVariables = cfg.environment;
          StandardOutPath = "/var/log/openproject-worker.log";
          StandardErrorPath = "/var/log/openproject-worker.error.log";
        };
      };

      openproject-cron = mkIf cfg.imap.enable {
        serviceConfig = {
          ProgramArguments = [ "${cfg.package}/bin/openproject-cron-step-imap" ];
          UserName = "openproject";
          StartInterval = 300;
          EnvironmentVariables = cfg.environment;
          StandardOutPath = "/var/log/openproject-cron.log";
          StandardErrorPath = "/var/log/openproject-cron.error.log";
        };
      };
    };

    services.postgresql = {
      enable = true;
      ensureDatabases = [ "openproject" ];
      ensureUsers = [{
        name = "openproject";
        ensureDBOwnership = true;
      }];
    };

  };
}
