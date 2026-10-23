# TycoonConsole

A Windows control panel for a self-hosted Minecraft Java server, designed for the Mob Spawner Tycoon project.

## Current scaffold

- Detects the PC's LAN IPv4 address.
- Reads the Minecraft server port from `server.properties` (default: 25565).
- Shows the public IPv4 address when an external IP lookup is reachable.
- Starts a selected Java server JAR with a 6 GB maximum heap.
- Opens the server, plugins, and mods folders.
- Includes a button to check the GitHub Releases page.

## Important: Minehut external hosting

Minehut's official guide requires an externally hosted Paper server to be configured for Minehut authentication and proxy protocol. A detected IP address alone does not make a server reachable.

Official instructions: https://support.minehut.com/hc/en-us/articles/33252734474899-How-to-Setup-a-Minehut-External-Hosted-Server

For standalone Paper, Minehut currently instructs operators to:

1. In `config/paper-global.yml`, set `proxies.proxy-protocol: true` (unless using TCPShield).
2. In `server.properties`, set `enforce-secure-profile=false`.
3. Add these JVM flags to the Java startup command:
   ```text
   -Dminecraft.api.services.host=https://api.minecraftservices.com/
   -Dminecraft.api.auth.host=https://authserver.mojang.com/
   -Dminecraft.api.account.host=https://api.mojang.com/
   -Dminecraft.api.profiles.host=https://api.mojang.com/
   -Dminecraft.api.session.host=https://api.minehut.com/mitm/proxy
   ```
4. In Minehut's External Server Settings, enter the public IP and the actual reachable Minecraft port, select proxy type **Other** for standalone Paper, and select DNS record type **Port** unless you have correctly configured an SRV record.

Review Minehut's current official instructions before enabling these settings, as they may change. Do not expose Remote Desktop or other administrative ports to the internet.

### Finding the right IP and port

- **LAN IP** is for devices on your home network; it is not the address Minehut should normally use.
- **Public IP** is detected from an external IP lookup. This does not prove that inbound connections can reach your PC.
- **Port** is read from `server.properties`, defaulting to `25565`. Router/firewall configuration, ISP restrictions such as CGNAT, or a tunnel may affect reachability.
- Do not enter a made-up Minehut hostname. Minehut's server name and player-facing address are configured on Minehut's side after external connectivity is working.
- A tunnel must support the protocol and networking behavior required by Minehut; do not assume any generic tunnel will work.

## Requirements

- Windows 10/11
- Java compatible with your chosen Minecraft server build (Minecraft 1.21.11 generally requires Java 21)
- A Paper server JAR for the plugin-based Mob Spawner Tycoon server

## Run from source

1. Download or clone this repository.
2. Run `Start-TycoonConsole.bat`.
3. Put your Paper server JAR in the `server` folder.
4. Review `server.properties` and the Minecraft EULA. The console blocks startup until `eula=true` is set by the operator after accepting the EULA.
5. Use **Start Server** to launch the server.

This is an initial source scaffold, not a signed installer or compiled EXE. The updater currently checks for a published GitHub release; automatic download, verification, and installation still need to be implemented.

## Mods and plugins

Paper plugins belong in `server/plugins/`. Fabric/Forge mods belong in `server/mods/` and require a compatible mod loader. Paper does not load Fabric/Forge mods directly. The console creates the mods folder for convenience but does not claim that arbitrary mods work with Paper.

## Resource pack

Minehut's external-server guide lists accepted resource-pack hosting domains and explains the `resource-pack` and optional `resource-pack-sha1` properties. Check the official guide before publishing the Mob Spawner Tycoon pack.

## Security and backups

Do not commit server credentials, access tokens, private IP details, or world backups. Keep regular backups of world folders, plugins, and configuration files.
