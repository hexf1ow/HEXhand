# HEXhand

Turns ChatGPT web into a coding agent that works in **your own folders** — on your machine,
or on a machine you reach over your own network.

HEXhand is a rebranded distribution of [CatDesk](https://github.com/Xeift/CatDesk) (MIT).
See [NOTICE](NOTICE) for attribution and the list of changes. The upstream documentation is kept
at [docs/CATDESK-UPSTREAM-README.md](docs/CATDESK-UPSTREAM-README.md).

## Two ways to run it

**1. Local (default)** — the app runs next to the folder it works in. Start it, open the URL it
prints, add that URL as a connector in ChatGPT.

**2. Remote (HEXhand extra)** — the app runs on a server, and a small connector runs next to the
folder on another machine. Every tool call is forwarded to the connector, so the agent edits that
machine's files while ChatGPT only ever talks to your server.

```
ChatGPT -> https://your-host/agent/<slug>/mcp -> HEXhand (container)
                                               -> connector (other machine)
                                               -> the folder you activated
```

## Quick start (prebuilt binary)

1. Download the archive for your platform from **Releases**.
2. Run the binary. It prints an MCP URL and a workspace slug.
3. In ChatGPT: add that URL as a connector, then ask it to work in your project.

Nothing else is installed — no Rust toolchain, no tunnel account.

## Build from source

```bash
git clone https://github.com/hexf1ow/HEXhand.git
cd HEXhand
cargo build --release      # binary at target/release/hexhand
```

Rust 1.85+ (edition 2024). The release profile uses LTO and strips symbols.

## Remote mode

On the machine that holds the files, run the connector inside the folder you want the agent to use:

```powershell
powershell -ExecutionPolicy Bypass -File hexhand-here.ps1 -Path "D:\some\folder"
```

Point the server at it:

```
CATDESK_REMOTE_URL=http://<connector-host>:3210/
CATDESK_REMOTE_TOKEN=<shared token>
```

The connector refuses any path outside the folder it was started in. The environment variable
names keep their original spelling so existing CatDesk connectors keep working.

## Configuration

Settings live in `~/.hexhand/config.toml` (created on first run). An older `~/.catdesk` folder is
carried over automatically the first time HEXhand starts.

## Licence

MIT, same as upstream. See [LICENSE](LICENSE). CatDesk is copyright (c) 2026 xeift.eth.
HEXhand is not affiliated with or endorsed by the CatDesk authors.
