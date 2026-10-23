# TycoonConsole

A Windows control panel for a self-hosted Minecraft Java server, designed for the Mob Spawner Tycoon project.

## Current scaffold

- Detects the PC's LAN IPv4 address.
- Reads the Minecraft server port from `server.properties` (default: 25565).
- Shows the public IPv4 address when an external IP lookup is reachable.
- Starts and stops a selected Java server JAR.
- Opens the server, mods, and configuration folders.
- Includes an update-check button that checks this repository's GitHub Releases page.

## Important networking note

A LAN address such as `192.168.x.x` is not normally reachable from outside your home. A public IP and port are usable only if your router/firewall or an approved tunnel makes that port reachable. The app must not guess a Minehut hostname, and it does not create a Minehut server name.

Before sharing any address with Minehut, confirm the current Minehut External Hosted Server requirements and whether your chosen connection method is supported. Never expose Remote Desktop or other admin ports to the internet.

## Requirements

- Windows 10/11
- Java compatible with your chosen Minecraft server build (Minecraft 1.21.11 generally requires Java 21)
- A downloaded Paper server JAR for the plugin-based Mob Spawner Tycoon server

## Run from source

1. Download or clone this repository.
2. Run `Start-TycoonConsole.bat`.
3. Choose the folder containing your server JAR, or use the default `server` folder.
4. Review `server.properties`, especially `server-port`, and accept the Minecraft EULA after reading it.
5. Use **Start Server** to launch the server.

This is an initial source scaffold, not a signed installer or compiled EXE. The updater can check for published releases; it cannot install a release until a release asset/package is published.

## Mods and plugins

Paper plugins belong in `plugins\`. Fabric/Forge mods belong in `mods\` and require a compatible mod loader. Paper does not load Fabric/Forge mods directly. TycoonConsole creates a `mods\` folder for convenience but does not claim that arbitrary mods work with Paper.

## Security

Do not commit server credentials, access tokens, private IP details, or world backups. Keep regular backups of `world\`, `world_nether\`, `world_the_end\`, `plugins\`, and configuration files.
