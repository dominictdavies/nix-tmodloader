{ config, lib, pkgs, ... }:
with lib;
let 
  cfg = config.services.tmodloader;

  worldSizeMap = { small = 1; medium = 2; large = 3; };
  valFlag = name: val: lib.optionalString (val != null) "-${name} \"${lib.escape ["\\" "\""] (toString val)}\"";
  boolFlag = name: val: lib.optionalString val "-${name}";
  
in
{
  options = {
    services.tmodloader = {
      enable = mkEnableOption "Enables or disables all tmodloader servers";

      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/tmodloader";
        description = "Data directory where worlds and sockets go";
      };

      makeAttachScripts = mkOption {
        type = types.bool;
        default = false;
        description = "Add attach scripts to environment.systemPackages";
      };

      servers = mkOption {
        default = { };
        description = "Servers to be created";

        type = types.attrsOf (types.submodule ({ name, ... }: {
          options = {
            enable = mkEnableOption "Enables or disables this specific terraria server";

            openFirewall = mkOption {
              type = types.bool;
              default = false;
              description = "Whether to open ports in the firewall";
            };

            port = mkOption {
              type = types.port;
              default = 7777;
              description = "Port to listen on";
            };

            autoStart = mkOption {
              type = types.bool;
              default = false;
              description = "Whether or not to start it's systemd service on boot";
            };

            package = mkOption {
              type = types.package;
              default = pkgs.tmodloader-server;
              description = "Server package to use";
            };

            players = mkOption {
              type = types.ints.u8;
              default = 255;
              description = "Sets the max number of players (from 1-255)";
            };

            password = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Sets the server password. Leave `null` for no password";
            };
            
            world = mkOption {
              type = types.nullOr types.path;
              default = null;
              description = ''
                The path to the world file (`.wld`) which should be loaded. If the
                specified path does not exist, a world will be autocreated with a size
                specified in -autocreate
              '';
            };

            autocreate = mkOption {
              type = types.enum [ "small" "medium" "large" ];
              default = "medium";
              description = "Size to autocreate world with";
            };

            banlist = mkOption {
              type = types.nullOr types.path;
              default = null;
              description = "Specifies the location of the banlist";
            };

            secure = mkOption {
              type = types.bool;
              default = false;
              description = "Adds addition cheat protection to the server";
            };

            noupnp = mkOption {
              type = types.bool;
              default = false;
              description = "Disables automatic port forwarding";
            };

            disableannouncementbox = mkOption {
              type = types.bool;
              default = false;
              description = "Disables the text announcements Announcement Box makes when pulsed from wire";
            };

            announcementboxrange = mkOption {
              type = types.nullOr types.ints.s32;
              default = null;
              description = "Sets the announcement box text messaging range in pixels, -1 for serverwide announcements.";
            };

            seed = mkOption {
              type = types.nullOr types.ints.u32;
              default = null;
              description = ''
                Specifies the world seed when using -autocreate. This will only actually work as
                a fallback for -world, so unless that's specified you'll have to manually set up
                the world by attaching to the socket
              '';
            };

            # modpack = mkOption {
              # type = types.nullOr types.path;
              # default = null;
              # description = "Sets the mod pack to load, causing only the specified mods to load";
            # };

            # modpath = mkOption {
              # type = types.nullOr types.path;
              # default = null;
              # description = "Sets the folder where manually installed mods will be loaded from";
            # };

            install = mkOption {
              type = types.listOf types.ints.u32;
              default = [];
              description = "List of workshop mod ids to install";
            };
            
          };
        }));
      };
    };
  };

  config = mkIf cfg.enable (
    let
      servers = filterAttrs (_: cfg: cfg.enable) cfg.servers;
      ports = mapAttrsToList (name: conf: conf.port)
        (filterAttrs (_: cfg: cfg.openFirewall) servers);

      counts = map (port: count (x: x == port) ports) (unique ports);

    in
    {
      assertions = [
        {
          assertion = all(x: x == 1) counts;
          message = "Two or more servers have conflicting ports";
        }
      ];

      environment.systemPackages = mkIf cfg.makeAttachScripts (
        mapAttrsToList (name: conf: pkgs.writeShellApplication {
          name = "tmodloader-${name}-attach";
          text = "${getExe pkgs.tmux} -S ${escapeShellArg cfg.dataDir}/${name}.sock attach";
        }) servers
      );
    
      users.users.terraria = {
        description = "Terraria server service user";
        group = "terraria";
        home = cfg.dataDir;
        createHome = true;
        isSystemUser = true;
        uid = config.ids.uids.terraria;
      };
      users.groups.terraria.gid = config.ids.gids.terraria;

      networking.firewall.allowedUDPPorts = ports;
      networking.firewall.allowedTCPPorts = ports;

      systemd.services = mapAttrs' (name: conf: 
      let
        flags = [
          "-nosteam"

          # THESE ARE NECESSARY in order to locate workshop mods
          # this is definitely not backwards compatible
          "-tmlsavedirectory ${cfg.dataDir}/${name}"
          "-steamworkshopfolder ${cfg.dataDir}/${name}/steamapps/workshop"

          (valFlag "port" conf.port)
          (valFlag "players" conf.players)
          (valFlag "password" conf.password)
          (valFlag "world" conf.world)
          (valFlag "autocreate" (builtins.getAttr conf.autocreate worldSizeMap))
          (valFlag "banlist" conf.banlist)
          (boolFlag "secure" conf.secure)
          (boolFlag "noupnp" conf.noupnp)
          (boolFlag "disableannouncementbox" conf.disableannouncementbox)
          (valFlag "announcementboxrange" conf.announcementboxrange)
          (valFlag "seed" conf.seed)

          # https://github.com/tModLoader/tModLoader/wiki/Command-Line
          # (valFlag "modpack" conf.modpack)
          # (valFlag "modpath" conf.modpath)
        ];

        tmuxCmd = "${getExe pkgs.tmux} -S ${escapeShellArg cfg.dataDir}/${name}.sock";

        updateWorkshop = pkgs.writeShellApplication {
          name = "tmodloader-${name}-update-workshop";
          runtimeInputs = with pkgs; [ steamcmd bash ];
          text = ''

            # install mods with manage-tModLoaderServer.sh
            echo UPDATING MODS
            # bash ${conf.package}/DedicatedServerUtils/manage-tModLoaderServer.sh \
              # install-mods \
              # -f ${escapeShellArg cfg.dataDir}/${name} \
              # --steamcmdpath ${pkgs.steamcmd}/bin/steamcmd

            steamcmd +force_install_dir \
              ${escapeShellArg cfg.dataDir}/${name} \
              +login anonymous \
              ${concatStringsSep " " (map (x: "+workshop_download_item 1281930 ${toString x}") conf.install)} \
              +quit

            # make enabled.json
            # first regular expression is to get file paths of all tmods
            # we then trim it to a single line by reomving all line breaks
            # we then remove the last comma and enclose it in a list to make it valid json
            # finally we write to Mods/enabled.json. If there are no mods, enabled.json will
            # be empty which is probably fine ??

            find ${escapeShellArg cfg.dataDir}/${name}/steamapps -regex ".*tmod" \
              | sed -E 's/.*\/(\w+)\.tmod/"\1",/' \
              | tr -d '\n' \
              | sed -E 's/(.*)./[\1]\n/' \
              > ${escapeShellArg cfg.dataDir}/${name}/Mods/enabled.json

            
          '';
        };

        stopScript = pkgs.writeShellApplication {
          name = "tmodloader-${name}-stop";
          text = ''
            echo KILLING TMUX

            if ! [ -d "/proc/$1" ]; then exit 0; fi

            lastline=$(${tmuxCmd} capture-pane -p | grep . | tail -n1)

            # If the service is not configured to auto-start a world, it will show the world selection prompt
            # If the last non-empty line on-screen starts with "Choose World", we know the prompt is open
            if [[ "$lastline" =~ ^'Choose World' ]]; then
              # In this case, nothing needs to be saved, so we can kill the process
              echo killed
              ${tmuxCmd} kill-session
            else
              # Otherwise, we send the `exit` command
              echo sending exit keys, will die soon
              ${tmuxCmd} send-keys Enter exit Enter exit Enter
            fi

            tail --pid="$1" -f /dev/null
          '';
        };

        startPreScript = pkgs.writeShellScript "tmodloader-${name}-start-pre" ''
          # if we don't reomve the existing socket we'll get a permission error
          if [ -f "${cfg.dataDir}/${name}.sock" ]; then rm ${escapeShellArg cfg.dataDir}/${name}.sock; fi;

          # if we don't make these permissive beforehand things could break
          # I'm not actually sure how this would work with two servers writing to these at
          # a time but that can be tested later :)
          touch /tmp/environment-server.log
          touch /tmp/server.log
          chmod 777 /tmp/environment-server.log
          chmod 777 /tmp/server.log

          # make install.txt
          mkdir -p ${escapeShellArg cfg.dataDir}/${name}/Mods
          echo "${concatStringsSep "\\n" (map toString conf.install)}" > ${escapeShellArg cfg.dataDir}/${name}/Mods/install.txt

          ${getExe updateWorkshop}
        '';

      in
      {
        name = "tmodloader-server-${name}";
        value = {
          enable = conf.enable;

          description = "tModLoader Server ${name}";
          wantedBy = mkIf conf.autoStart [ "multi-user.target" ];
          after = [ "network.target" ];

          serviceConfig = {
            User = "terraria";
            Group = "terraria";
            Type = "forking";
            GuessMainPID = true;
            UMask = 7;

            ExecStartPre = "${startPreScript}";
            ExecStart = "${tmuxCmd} new -d ${getExe conf.package} ${concatStringsSep " " flags}";
            ExecStop = "${getExe stopScript} $MAINPID";

            TimeoutStartSec = "5min";
          };

        };
      }) servers;
    }
  );
  
}
