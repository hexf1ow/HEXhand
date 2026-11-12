# HEXhand connectors

A connector is a small program that sits next to a folder and lets a HEXhand server
somewhere else work in it. Same ten tools, same wire format, three platforms.

| Platform | File | Start it with |
|---|---|---|
| Windows | `windows/hexhand-here.cmd` | double-click, or `hexhand-here.cmd D:\work\site` |
| Windows (right-click menu) | `windows/install-launcher.ps1` | run once **in an admin PowerShell** — adds **HEXhand here** to the folder right-click menu and reserves the port so later clicks need no admin |
| Linux | `hexhand-here.sh` | `./hexhand-here.sh ~/work/site` |
| macOS | `hexhand-here.sh` | `./hexhand-here.sh ~/work/site` |

The workspace is the folder you start it in. Every path is checked against that folder —
anything outside it is refused, so the connector cannot touch the rest of the disk.

## Port and token

- Listens on **3210** (override with `HEXHAND_CONNECTOR_PORT`).
- Requires `Authorization: Bearer <token>` on every request.
- Windows: the token is in `%USERPROFILE%\.hexhand\connector\connector_token.txt`.
- Linux/macOS: generated on first run into `~/.hexhand/connector_token`.

Give the same token to the server:

```bash
CATDESK_REMOTE_URL=http://<connector-host>:3210/
CATDESK_REMOTE_TOKEN=<token>
```

## Requirements

- Windows: PowerShell 5.1 (built in).
- Linux/macOS: Python 3.9+ (standard library only — nothing to install).

## Windows: run the installer once as admin

`install-launcher.ps1` does two things you only want to do once:

- adds **HEXhand here** to the right-click menu of folders and folder backgrounds;
- reserves TCP 3210 for your user (`netsh http add urlacl`). **Without this the menu
  starts and immediately fails to bind**, because Windows will not let a normal user open
  an HTTP listener — it looks like the menu is broken. Run it once in an elevated
  PowerShell and that is the last time you need admin.

## Firewall

Only the HEXhand server needs to reach the connector. Allow TCP 3210 from that one host:

```powershell
New-NetFirewallRule -DisplayName "HEXhand connector" -Direction Inbound -Protocol TCP `
  -LocalPort 3210 -RemoteAddress <server-ip> -Action Allow
```

```bash
sudo ufw allow from <server-ip> to any port 3210 proto tcp
```

## Security

The token is the only authentication. Treat it like a password, keep the port off the public
internet (reach it over a LAN or VPN), and stop the connector when you are done.
