<p align="center">
  <img src="assets/hexhand-wordmark.png" alt="HEXhand" width="600">
</p>

<p align="center">
  <b>Turn ChatGPT web into a coding agent that works in your own folders.</b><br>
  No plugins, no cloud workspace, no copy-pasting code back and forth.
</p>

<p align="center">
  <a href="https://github.com/hexf1ow/HEXhand/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/hexf1ow/HEXhand?color=0a84ff"></a>
  <a href="LICENSE"><img alt="Licence" src="https://img.shields.io/badge/licence-MIT-green"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platform-linux%20%7C%20macOS%20%7C%20windows-lightgrey">
</p>

---

## What HEXhand is

HEXhand is a small program that runs on **your** machine and exposes your project folder to ChatGPT
through the Model Context Protocol (MCP). ChatGPT can then read files, write files, search, run
commands and check the output — on your disk, with your toolchain, in your folder.

- **Your files stay yours.** Nothing is uploaded. HEXhand serves the folder to ChatGPT on request.
- **Your machine does the work.** Builds, tests and scripts run locally, not in someone's cloud.
- **One file to install.** A single binary. No Node, no Docker, no Rust toolchain.
- **No tunnel account, no relay, no quota.** Other builds of this tool send your traffic through a
  third-party tunnel service and stop working when the free quota runs out. HEXhand serves on its own
  port and lets you put your own name and certificate in front — unlimited, and it cannot be metered.
- **Optional remote mode.** Keep HEXhand running on a server and drive a folder on a different
  computer through a small connector (see [Remote mode](#remote-mode)).

HEXhand is a rebranded distribution of [CatDesk](https://github.com/Xeift/CatDesk) (MIT).
See [NOTICE](NOTICE) for attribution and the exact list of changes.

## What it costs: nothing

There is no subscription, no seat count, no usage meter and no account with us.

| Piece | Cost |
|---|---|
| HEXhand itself | Free — MIT licence, source in this repo |
| Prebuilt binaries | Free — Linux, macOS (Intel + Apple Silicon), Windows |
| Caddy (HTTPS in front of it) | Free — open source |
| DuckDNS (name for a changing home IP) | Free |
| ChatGPT connector | Uses the plan you already pay for |

The only thing you provide is the machine it runs on — a spare PC, a NAS or a small VPS.
That is the whole cost of ownership.

## What you need

| | |
|---|---|
| ChatGPT | A plan that allows custom connectors (Plus, Pro, Team or Enterprise) |
| A folder | The project you want ChatGPT to work in |
| A way to reach it | Optional. Run HEXhand on your own network and point Caddy at it — see [Run it free on your own server](#run-it-free-on-your-own-server). A free DuckDNS name is enough. **No tunnel account, no relay service, no quota.** |

> Older CatDesk builds forced an ngrok account before they would start. HEXhand does not: with no
> token configured it starts in self-hosted mode and serves on its local port. A tunnel is opt-in
> (`tunnelEnabled = true` in the config) for people who want a public URL without running a proxy.

## Install

Grab the file for your platform from
[**Releases**](https://github.com/hexf1ow/HEXhand/releases/latest) and run it.

**Linux**

```bash
curl -L -o hexhand https://github.com/hexf1ow/HEXhand/releases/latest/download/hexhand-linux-x64
chmod +x hexhand
./hexhand
```

**macOS** (Apple Silicon shown; use `hexhand-darwin-x64` on Intel)

```bash
curl -L -o hexhand https://github.com/hexf1ow/HEXhand/releases/latest/download/hexhand-darwin-arm64
chmod +x hexhand
xattr -d com.apple.quarantine hexhand 2>/dev/null   # clears the "unverified developer" flag
./hexhand
```

**Windows**

Download `hexhand-win32-x64.exe` from
[Releases](https://github.com/hexf1ow/HEXhand/releases/latest) and double-click it, or run it from a
terminal:

```powershell
.\hexhand-win32-x64.exe
```

> Windows SmartScreen will warn you the first time because the binary is not code-signed. Choose
> **More info → Run anyway**.

Verify a download against the published checksums: `sha256sum -c SHA256SUMS` (Linux/macOS) or
`Get-FileHash` (Windows). `SHA256SUMS` is attached to every release.

## First run — five minutes

1. **Start HEXhand** in the folder you want ChatGPT to work in:

   ```bash
   cd ~/projects/my-app
   hexhand
   ```

2. **Pick a mode** — *Control Computer* is the usual choice. That is the whole onboarding: no
   account, no token, no sign-up.

3. **Copy the MCP URL** it shows, e.g.

   ```
   http://127.0.0.1:3200/AbCdEf1234567890/mcp
   ```

   The `<slug>` is a random 16-character identifier generated for you. **It is the only
   credential** — treat the URL like a password.

   That URL is local. To reach it from ChatGPT, put a reverse proxy in front (next section) or turn
   on the optional tunnel.

4. **Add it to ChatGPT:** *Settings → Connectors → Add custom connector*, paste the URL, save.
   (On some plans this appears as *Developer mode → Add connector*.)

5. **Test it.** Ask ChatGPT: *"List the files in this project and tell me what it does."*

## What ChatGPT can do with it

| Tool | What it does |
|---|---|
| `run_command` | Run a shell command in the folder and return the output |
| `start_command` | Start a long-running command in the background |
| `poll_command` | Read more output from a background command |
| `cancel_command` | Stop a background command |
| `read` | Read one or more files |
| `write` | Create or overwrite a file |
| `edit` | Replace an exact snippet inside a file |
| `search` | Search text across the folder |
| `delete` | Delete a file or folder |
| `hexhand_instruction` | Ask for the rules of the current workspace |

Working-folder rules are enforced: any path outside the folder HEXhand was started in is refused.

## Remote mode

Run HEXhand on a server and let it drive a folder on another machine — a build box, a Windows
desktop, a lab machine you don't want to install on.

| Where the folder lives | How it works |
|---|---|
| Same machine as HEXhand | Run the binary in the folder. Nothing else needed. |
| Another Windows machine | `hexhand-here.ps1` connector (included) |
| Another Linux / macOS machine | Run the binary there, or use the connector script — see [connectors](connector/) |

**On the machine that holds the files**, start the connector inside that folder:

```powershell
powershell -ExecutionPolicy Bypass -File hexhand-here.ps1 -Path "D:\work\site"
```

It listens on port 3210, accepts only requests with the shared bearer token, and refuses any path
outside the folder it was started in.

**On the server**, point HEXhand at it:

```bash
CATDESK_REMOTE_URL=http://<connector-host>:3210/ \
CATDESK_REMOTE_TOKEN=<shared token> \
hexhand
```

Every tool call is then forwarded to the connector, so the files ChatGPT edits live on the other
machine. The variable names keep their original spelling so existing CatDesk connectors keep working.

## Run it free on your own server

The whole stack is free: HEXhand in Docker, Caddy for HTTPS, DuckDNS for a name when your home IP
changes. Nothing here needs a paid service or an account with us.

```
Internet ──► DuckDNS name ──► Caddy (HTTPS) ──► HEXhand container ──► connector ──► your folder
```

**1. Get a name for your IP** — sign in at [duckdns.org](https://www.duckdns.org), create a
subdomain, and keep it pointed at your connection with their updater container:

```bash
docker run -d --name duckdns --restart=unless-stopped \
  -e SUBDOMAINS=yourname -e TOKEN=<duckdns-token> -e LOG_FILE=false \
  linuxserver/duckdns
```

**2. Start HEXhand with limits** — the limits are what stop a runaway command from eating the machine:

```bash
docker build -t hexhand .
docker run -d --name hexhand --restart=unless-stopped \
  --memory 1g --memory-swap 1g --cpus 1.5 --pids-limit 512 \
  -v "$HOME/.hexhand:/root/.hexhand" \
  hexhand
```

**3. Put Caddy in front** so it gets a real certificate (`Caddyfile`):

```
yourname.duckdns.org {
    reverse_proxy hexhand:3201
}
```

Open ports **80/443** to Caddy only. The HEXhand port itself stays on the Docker network.

**4. Add the URL in ChatGPT** — `https://yourname.duckdns.org/<slug>/mcp`.

**Video walkthroughs of DuckDNS** (watch one, the rest is copy-paste):

- Techno Tim — *Self-Host All Your Homelab Services with DuckDNS* — https://www.youtube.com/watch?v=bVmUV1G5wpI
- Awesome Open Source — *DuckDNS for Routing Internet Traffic to your Home Lab* — https://www.youtube.com/watch?v=Dm5MyuUdq2s

### Why run it in a container

A container does not make an agent safe on its own — what makes it safe is the boundary you put
around it:

- **cgroup limits** (`--memory`, `--cpus`, `--pids-limit`) stop a runaway build or a fork bomb from
  taking the host down; the kernel refuses the allocation instead of the machine swapping to death.
- **restart policy** (`--restart=unless-stopped`) brings it back by itself after a crash or a reboot.
- **folder guard** in the app and the connector — every path is checked, so it cannot wander outside
  the one folder you pointed it at.
- **no host filesystem** beyond the single volume you mount, and no privileged mode.

That is the combination worth advertising: bounded CPU, bounded memory, bounded files, restarts by
itself.

## Connector icon (ChatGPT)

ChatGPT shows the connector icon very small, so the artwork is supplied in the sizes it actually
renders from — square, transparent, tightly cropped:

| File | Size | Use |
|---|---|---|
| `assets/icons/hexhand-512.png` | 512×512 | connector icon (recommended upload) |
| `assets/icons/hexhand-256.png` | 256×256 | stores that ask for smaller |
| `assets/icons/hexhand-128.png` | 128×128 | minimum size |
| `assets/icons/hexhand.ico` | 16–256 | Windows executable icon |

In ChatGPT: *Settings → Connectors → your HEXhand connector → Edit → icon → upload* the 512px file.

## Configuration

Settings live in `~/.hexhand/config.toml` (Windows: `%USERPROFILE%\.hexhand\config.toml`).
If you used CatDesk before, an existing `~/.catdesk` folder is carried over automatically on first
start — you keep your slug and settings.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Could not listen on port 3200` | Another HEXhand/CatDesk instance is already running. Close it, or let HEXhand pick the next port. |
| ChatGPT says the connector failed | Check the tunnel is up: open the MCP URL in a browser — you should get a JSON-RPC error, not a connection failure. |
| ChatGPT cannot reach the URL | A local URL is not reachable from outside. Put Caddy in front with a real hostname (see the deployment section), or enable the optional tunnel. |
| A command runs forever | Ask ChatGPT to use `start_command`, then `poll_command`, then `cancel_command`. |
| Windows: "unverified publisher" | Expected — the binary is not code-signed. *More info → Run anyway*. |

## Build from source

```bash
git clone https://github.com/hexf1ow/HEXhand.git
cd HEXhand
cargo build --release      # -> target/release/hexhand
```

Rust 1.85+ (edition 2024). The release profile uses LTO and strips symbols. Container builds are
supported too — see `deploy/Dockerfile` and `deploy/entrypoint.sh`.

## Security notes

- The `<slug>` in the URL is the only thing protecting your workspace. Anyone with the URL can use
  every tool. Rotate it by onboarding again if it leaks.
- HEXhand serves one folder: the one it was started in. Paths outside it are rejected.
- The tunnel is outbound from your machine; you never open a port on your router.

## Licence and attribution

MIT — see [LICENSE](LICENSE).

HEXhand is a rebranded distribution of **CatDesk**, copyright (c) 2026 xeift.eth, also MIT.
Upstream documentation is kept in [docs/CATDESK-UPSTREAM-README.md](docs/CATDESK-UPSTREAM-README.md).
HEXhand is not affiliated with or endorsed by the CatDesk authors.
