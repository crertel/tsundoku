{ self }:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.tsundoku;

  package =
    if cfg.package != null
    then cfg.package
    else self.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Auto-provision the local Postgres unless the user has supplied creds
  # for an external DB. Explicit true/false still wins.
  effectiveProvision =
    if cfg.database.provision != null
    then cfg.database.provision
    else cfg.databaseUrl == null && cfg.database.passwordFile == null;

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

  beamFlagsStr = lib.concatStringsSep " " cfg.beamFlags;
in
{
  options.services.tsundoku = {
    enable = lib.mkEnableOption "Tsundoku, a personal bookmarks app";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        The tsundoku release package. Defaults to the flake's
        own packages.default; override to swap in a custom build.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "tsundoku";
      description = "System user the service runs as.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "tsundoku";
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

    logLevel = lib.mkOption {
      type = lib.types.enum [ "emergency" "alert" "critical" "error" "warning" "notice" "info" "debug" ];
      default = "info";
      description = "Elixir Logger level. Maps to LOG_LEVEL.";
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
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = ''
          Auto by default (null): provisions a local PostgreSQL service
          iff neither databaseUrl nor database.passwordFile is set. Set
          to true to force provisioning, or false to point at an
          external DB you manage yourself.
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
        default = "tsundoku";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "tsundoku";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to a file containing the DB password. Ignored when the
          local Postgres is being provisioned (peer auth is used).
        '';
      };

      poolSize = lib.mkOption {
        type = lib.types.ints.positive;
        default = 10;
        description = "Ecto connection pool size. Maps to POOL_SIZE.";
      };

      ipv6 = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open the DB socket over IPv6. Maps to ECTO_IPV6.";
      };
    };

    oban = {
      metadataConcurrency = lib.mkOption {
        type = lib.types.ints.positive;
        default = 5;
        description = ''
          Number of metadata-fetch workers run in parallel. Per-domain
          serialization is enforced inside the worker so the crawler
          still doesn't hit the same host concurrently. Maps to
          OBAN_METADATA_CONCURRENCY.
        '';
      };

      pruneMaxAgeDays = lib.mkOption {
        type = lib.types.ints.positive;
        default = 7;
        description = ''
          Days to keep completed/discarded Oban jobs before the Pruner
          deletes them. Maps to OBAN_PRUNE_MAX_AGE_DAYS.
        '';
      };
    };

    beamFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "+P" "1048576" "+K" "true" ];
      description = ''
        Extra flags passed to the BEAM VM via ELIXIR_ERL_OPTIONS.
        See `erl -help` for available flags (e.g. +P max processes,
        +Q max ports, +S schedulers, +K kernel poll, +sbwt scheduler
        busy-wait, +A async threads).
      '';
    };

    cookieFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing the Erlang distribution cookie. Only
        relevant if you actually use distribution (see `distribution`).
        Anyone with this cookie + network access to an EPMD-exposed node
        gets full RCE, so keep it secret. If null, the cookie baked into
        the release at build time is used.
      '';
    };

    nodeName = lib.mkOption {
      type = lib.types.str;
      default = "tsundoku";
      description = ''
        Erlang node name (or short/long name depending on
        `distribution`). Maps to RELEASE_NODE.
      '';
    };

    distribution = lib.mkOption {
      type = lib.types.enum [ "none" "sname" "name" ];
      default = "sname";
      description = ''
        Erlang distribution mode. `none` disables distribution entirely
        (no EPMD, no `-name`/`-sname`); `sname` uses a short name on the
        local host; `name` uses a fully-qualified long name. Maps to
        RELEASE_DISTRIBUTION.
      '';
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
      description = "Tsundoku service user";
    };

    users.groups.${cfg.group} = { };

    services.postgresql = lib.mkIf effectiveProvision {
      enable = lib.mkDefault true;
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [{
        name = cfg.database.user;
        ensureDBOwnership = true;
      }];
    };

    systemd.services.tsundoku = {
      description = "Tsundoku";
      wantedBy = [ "multi-user.target" ];
      after =
        [ "network.target" ]
        ++ lib.optional effectiveProvision "postgresql.service";
      requires = lib.optional effectiveProvision "postgresql.service";

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
        LOG_LEVEL = cfg.logLevel;
        POOL_SIZE = toString cfg.database.poolSize;
        OBAN_METADATA_CONCURRENCY = toString cfg.oban.metadataConcurrency;
        OBAN_PRUNE_MAX_AGE_DAYS = toString cfg.oban.pruneMaxAgeDays;
        RELEASE_NODE = cfg.nodeName;
        RELEASE_DISTRIBUTION = cfg.distribution;
      } // lib.optionalAttrs (cfg.urlPort != null) {
        PHX_URL_PORT = toString cfg.urlPort;
      } // lib.optionalAttrs cfg.database.ipv6 {
        ECTO_IPV6 = "true";
      } // lib.optionalAttrs (beamFlagsStr != "") {
        ELIXIR_ERL_OPTIONS = beamFlagsStr;
      } // cfg.extraEnvironment;

      serviceConfig = {
        Type = "exec";
        User = cfg.user;
        Group = cfg.group;
        StateDirectory = "tsundoku";
        WorkingDirectory = "/var/lib/tsundoku";

        LoadCredential =
          [ "secret_key_base:${cfg.secretKeyBaseFile}" ]
          ++ lib.optional (cfg.cookieFile != null) "cookie:${cfg.cookieFile}"
          ++ lib.optional
            (!effectiveProvision && cfg.database.passwordFile != null)
            "db_password:${cfg.database.passwordFile}";

        # Run database migrations on every start, then start the release.
        # If a cookie file is provided, source it into RELEASE_COOKIE before exec.
        ExecStartPre =
          "${package}/bin/${package.pname or "tsundoku"} eval 'Tsundoku.Release.migrate()'";
        ExecStart =
          let
            bin = "${package}/bin/${package.pname or "tsundoku"}";
          in
          if cfg.cookieFile != null
          then
            # Read the cookie file into RELEASE_COOKIE just before the release boots.
            pkgs.writeShellScript "tsundoku-start" ''
              export RELEASE_COOKIE="$(cat "$CREDENTIALS_DIRECTORY/cookie")"
              exec ${bin} start
            ''
          else "${bin} start";

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
  };
}
