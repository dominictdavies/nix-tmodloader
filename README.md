# nix-tmodloader

Run an arbitrary number of tmodloader servers that automatically installs and updates your mods and everything. This is basically just a flake to allow you to host tmodloader servers on nix machines.

This module is basically a heavily modified version of the [terraria-server option](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/games/terraria.nix) in nixpkgs, made to be more in the style of [nix-minecraft](https://github.com/Infinidoge/nix-minecraft) in that you should be able to run multiple servers at a time

I'm also not exactly sure how backwards compatible it is, given that mod installs switched over to workshop recently (and I'm not even sure if you can download older versions of mods anymore).

## a minimal example

to get a Calamity Mod server up and running only the following is needed:
```nix
services.tmodloader.enable = true;
services.tmodloader.servers.mycalamityserver = {
  enable = true;
  install = [ 2824688072 2824688266 ];
};
```

This will by default create a service that does not autostart that will spin up your server. You can start this service by running `systemctl start tmodloader-server-mycalamityserver`.

You will be prompted to create a world and set number of players and ports and such since none of these were provided as arguments in the derivation. You can, however, provide all of these arguments. Please read the options in `module/default.nix` for more options.

### notes

It is largely untested at the moment, especially with respect to running multiple servers at once. There are a couple hacky solutions to problems which may pose problems in the future but I'll update this as I test it and it **definitely** works for a single server instance at least, so I'll take my wins where I can get them.

While I'm not new to nix, I'm relatively new to actually using it beyond just maintaining my dotfiles (and am hopeless at flakes) so if there's things I could do more idiomatically please tell me.

### TODO
- [x] optionally add an attach command to environment.systemPackages
- [x] actually test it with multiple servers
- [x] actually test out all the options beyond just a minimal exapmle
- [ ] somehow run the update script in a forking process. Currently, the update script (all the steamcmd stuff) runs in `ExecStartPre`. This is bad because it means it takes seconds for the service to start. The issue is, I can't seem to get a forking tmux process to stay alive long enough when running anything other than \*just\* the terraria server. If you know what's wrong, please help me. What I've tried that doesn't work:

`${tmuxCmd} -d new ${bash script that first updates and then runs tmodloader}`

`${tmuxCmd} -d new bash ${bash script that first updates and then runs tmodloader}`

`${tmuxCmd} -d new bash -c "${update script}; ${run terraria script}"`

- [ ] figure out something less hacky for logging. tModLoader wants to write it's logs in it's install directory which happens to be mounted read only. To fix this, I symlink tModLoader-Logs to /tmp and ensure that the files it's going to be writing to have appropriate permissions in ExecStartPre, but this is absolutely not a perfect solution.

