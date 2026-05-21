{ self }:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.bookmark-server;

  package =
    if cfg.package != null
    then cfg.package
    else self.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Build a DATABASE_URL from the structured options if the user hasn't
  # passed one verbatim. Password (if any) is read from a file at start
  # by the systemd ExecStartPre.
  defaultDbUrl =
    let
      host = cfg.database.host;
      port = toString cfg.database.port;
      user = cfg.database.user;
      name = cfg.database.name;
    in
    "ecto://${user}@${host}:${port}/${name}";
in
{
  options.services.bookmark-server = {
    enable = lib.mkEnableOption "Bookmark Server, a personal bookmarks app";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        The bookmark_server release package. Defaults to the flake's
        own packages.default; override to swap in a custom build.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "bookmark-server";
      description = "System user the service runs as.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "bookmark-server";
      description = "System group the service runs as.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4000;
      description = "TCP port to listen on.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Address to bind the HTTP listener to. Default keeps it
        loopback-only; put a reverse proxy in front and override if
        you want it externally reachable.
      '';
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = ''
        Public hostname Phoenix uses when generating URLs. Should
        match what your reverse proxy serves.
      '';
    };

    scheme = lib.mkOption {
      type = lib.types.enum [ "http" "https" ];
      default = "http";
      description = "Scheme used in generated URLs.";
    };

    urlPort = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = ''
        Public port in generated URLs. Defaults to 443 for https and
        the listening port for http.
      '';
    };

    checkOrigin = lib.mkOption {
      type = lib.types.either lib.types.bool (lib.types.listOf lib.types.str);
      default = [ "//localhost" ];
      description = ''
        Comma-separated origins LiveView accepts. Set true to accept
        any (insecure). For example, [ "//bookmarks.example.com" ].
      '';
    };

    secretKeyBaseFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to a file containing the Phoenix SECRET_KEY_BASE. Generate
        with: openssl rand -base64 48. Must be readable by the service.
      '';
    };

    databaseUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Full ecto://USER:PASS@HOST/DATABASE URL. If null (default), one
        is constructed from the database.* options below.
      '';
    };

    database = {
      provision = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          When true, enables a local PostgreSQL service, creates the
          database, and gives the service peer auth. When false, you
          must point database.host/port/user at a reachable Postgres
          and supply database.passwordFile (or set databaseUrl).
        '';
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "/run/postgresql";
        description = "PG host. Default uses the local Unix socket.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 5432;
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "bookmark_server";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "bookmark-server";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to a file containing the DB password. Ignored when
          database.provision is true (peer auth is used).
        '';
      };
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment variables passed to the service.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      group = cfg.group;
      isSystemUser = true;
      description = "Bookmark Server service user";
    };

    users.groups.${cfg.group} = { };

    services.postgresql = lib.mkIf cfg.database.provision {
      enable = lib.mkDefault true;
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [{
        name = cfg.database.user;
        ensureDBOwnership = true;
      }];
    };

    systemd.services.bookmark-server = {
      description = "Bookmark Server";
      wantedBy = [ "multi-user.target" ];
      after =
        [ "network.target" ]
        ++ lib.optional cfg.database.provision "postgresql.service";
      requires = lib.optional cfg.database.provision "postgresql.service";

      environment = {
        PORT = toString cfg.port;
        PHX_LISTEN_IP = cfg.listenAddress;
        PHX_HOST = cfg.host;
        PHX_SCHEME = cfg.scheme;
        DATABASE_URL =
          if cfg.databaseUrl != null then cfg.databaseUrl else defaultDbUrl;
        SECRET_KEY_BASE_FILE = "%d/secret_key_base";
        PHX_CHECK_ORIGIN =
          if builtins.isBool cfg.checkOrigin
          then (if cfg.checkOrigin then "*" else "")
          else lib.concatStringsSep "," cfg.checkOrigin;
      } // lib.optionalAttrs (cfg.urlPort != null) {
        PHX_URL_PORT = toString cfg.urlPort;
      } // cfg.extraEnvironment;

      serviceConfig = {
        Type = "exec";
        User = cfg.user;
        Group = cfg.group;
        StateDirectory = "bookmark-server";
        WorkingDirectory = "/var/lib/bookmark-server";

        LoadCredential = [
          "secret_key_base:${cfg.secretKeyBaseFile}"
        ] ++ lib.optional
          (!cfg.database.provision && cfg.database.passwordFile != null)
          "db_password:${cfg.database.passwordFile}";

        # Run database migrations on every start, then start the release.
        ExecStartPre =
          "${package}/bin/${package.pname or "bookmark_server"} eval 'BookmarkServer.Release.migrate()'";
        ExecStart =
          "${package}/bin/${package.pname or "bookmark_server"} start";

        Restart = "on-failure";
        RestartSec = "5s";

        # Lock the service down.
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        NoNewPrivileges = true;
      };
    };

    assertions = [
      {
        assertion =
          cfg.database.provision
          || cfg.databaseUrl != null
          || cfg.database.passwordFile != null;
        message =
          "services.bookmark-server: when database.provision is false, set databaseUrl or database.passwordFile.";
      }
    ];
  };
}
