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
        default = "/lib/var/tmodloader";
        description = "Data directory where worlds and sockets go";
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
                The path to the world file (`.wld`) which should be loaded.
                If no world exists at this path, one will be created with the size
                specified by `autoCreatedWorldSize
              '';
            };

            autocreate = mkOption {
              type = types.enum [ "small" "medium" "large" ];
              default = "medium";
              description = ''
                Specifies the size of the auto-created world if `worldPath` does not
                point to an existing world.
              '';
            };

            banlist = mkOption {
              type = types.nullOr types.path;
              default = null;
              description = "Specifies the location of the banlist";
            };

            secure = mkOption {
              type = types.boolean;
              default = false;
              description = "Adds addition cheat protection to the server";
            };

            noupnp = mkOption {
              type = types.boolean;
              default = false;
              description = "Disables automatic port forwarding";
            };

            disableannouncementbox = mkOption {
              type = types.boolean;
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
              description = "Specifies the world seed when using -autocreate";
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
              description = ''
                List of workshop ids to install
              '';
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
    
      users = {
        users.tmodloader = {
          description = "tModLoader server service user";
          group = "tmodloader";
          home = cfg.dataDir;
          createHome = true;
          uid = config.ids.uids.terraria;
        };
        groups.tmodloader.gid = config.ids.gids.terraria;
      };

      networking.firewall.allowedUDPPorts = ports;
      networking.firewall.allowedTCPPorts = ports;

      systemd.services = mapAttrs' (name: conf: 
      let

        flags = [
          "-nosteam"
          "-tmlsavedirectory ${cfg.dataDir}/${name}"
          "-steamworkshopfolder ${cfg.dataDir}/${name}/steamapps/workshop"

          (valFlag "port" conf.port)
          (valFlag "players" conf.players)
          (valFlag "password" conf.password)
          (valFlag "world" conf.world)
          (valFlag "autocreate" (builtins.getAttr conf.autoCreatedWorldSize worldSizeMap))
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

        stopScript = pkgs.writeShellScript "tmodloader-${name}-stop" ''
          # from: https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/games/terraria.nix
          if ! [ -d "/proc/$1" ]; then;  exit 0;  fi

          lastline=$(${tmuxCmd} capture-pane -p | grep . | tail -n1)

          # If the service is not configured to auto-start a world, it will show the world selection prompt
          # If the last non-empty line on-screen starts with "Choose World", we know the prompt is open
          if [[ "$lastline" =~ ^'Choose World' ]]; then
            # In this case, nothing needs to be saved, so we can kill the process
            ${tmuxCmd} kill-session
          else
            # Otherwise, we send the `exit` command
            ${tmuxCmd} send-keys Enter exit Enter
          fi

          # Wait for the process to stop
          tail --pid="$1" -f /dev/null
        '';

        attachScript = pkgs.writeShellScript "tmodloader-${name}-attach" ''
          {getExe pkgs.tmux} -S ''${escapeShellArg cfg.dataDir}/${name}.sock attach
        '';

        startScript = pkgs.writeShellScript "tmodloader-${name}-start" ''
          # attach script is ${attachScript}
          # this is here so that we know for sure it's somewhere in nixpkgs
          # I don't know how to do this better I'm bad at nix
        
          # make install.txt
          mkdir -p ${cfg.dataDir}/${name}/Mods
          echo ${concatStringsSep "\n" conf.install} > ${cfg.dataDir}/${name}/Mods/install.txt
      
          # install mods with manage-tModLoaderServer.sh
          sh ${conf.package}/DedicatedServerUtils/manage-tModLoaderServer.sh install-mods -f ${escapeShellArg cfg.dataDir}/${name}

          # make enabled.json
          # first regular expression is to get file paths of all tmods
          # we then trim it to a single line by reomving all line breaks
          # we then remove the last comma and enclose it in a list to make it valid json
          # finally we write to Mods/enabled.json

          find ${escapeShellArg cfg.dataDir}/${name}/steamapps -regex ".*tmod" \
            | sed -E 's/.*\/(\w+)\.tmod/"\1",/' \
            | tr -d '\n' \
            | sed -E 's/(.*)./[\1]/' \
            > ${escapeShellArg cfg.dataDir}/${name}/Mods/enabled.json

          # start server with arguments
          ${getExe pkgs.tmux} -S ${escapeShellArg cfg.dataDir}/${name}.sock ${getExe conf.package} ${concatStringsSep " " flags}";
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
            User = "tmodloader";
            Group = "tmodloader";
            UMask = 007;
            WorkingDirectory = "${cfd.dataDir}/${name}";

            GuessMainPID = true;

            Type = "forking";

            ExecStop = "${stopScript} $MAINPID";
            ExecStart = "${startScript}";
          };

        };
      }) servers;
    }
  );
  
}
