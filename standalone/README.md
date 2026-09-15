# OpenCode - standalone Docker

A standalone Docker Compose build of [OpenCode](../README.md) for people running
Home Assistant **Core in a plain Docker container** (or anywhere else without
Home Assistant OS / Supervisor) — no `hassio`/Supervisor required.

This is a separate build from the `ha_opencode`/`ha_opencode_beta` Supervisor
add-ons in this repo. It ships the same terminal, MCP tool server, LSP, and
safe config-writing pipeline, adapted to run without Ingress, without the
Supervisor API, and without Supervisor-managed mounts:

| Supervisor add-on | Standalone |
|---|---|
| Auto-injected `SUPERVISOR_TOKEN`, proxied through `http://supervisor/core/api` | You supply `HA_URL` + a long-lived `HA_ACCESS_TOKEN`, used directly against Home Assistant Core |
| Home Assistant Ingress handles auth and serves the UI | A built-in "front door" proxy serves the UI directly; optional HTTP Basic Auth (`WEB_USERNAME`/`WEB_PASSWORD`) |
| `homeassistant_config`/`local_apps`/`all_app_configs` Supervisor mount types | Plain Docker bind mounts you configure yourself |
| Configuration tab (`config.yaml` options) | Environment variables (`.env`) |

## Quickstart

1. `cp .env.example .env` and fill in at least `HA_URL` and `HA_ACCESS_TOKEN`.
   - In Home Assistant: click your profile icon (bottom left) → scroll to
     **Long-Lived Access Tokens** → **Create Token**. Paste it into `.env`.
2. Set `HA_CONFIG_DIR` in `.env` to your real Home Assistant config directory
   (the one with `configuration.yaml` in it).
3. `docker compose up -d --build`
4. Open `http://<host>:8099/` — you'll land in the terminal. Run `opencode`,
   then `/connect` to add an AI provider (Anthropic/OpenAI/Google/OpenCode
   Zen/70+ others — same as the add-on).

On Raspberry Pi / other ARM64 hosts, set `BUILD_ARCH=aarch64` in `.env` first.

## Security

Home Assistant Ingress normally sits in front of the add-on and handles login
for you. There is no equivalent here — whatever you publish port 8099 to is
reachable by anyone who can reach it, full stop:

- **Simplest**: only bind it to localhost or a trusted LAN, or put it behind
  a reverse proxy / VPN / Cloudflare Access / Tailscale that you already trust.
- **Built-in option**: set both `WEB_USERNAME` and `WEB_PASSWORD` in `.env` to
  require HTTP Basic Auth on the front door. It's basic — fine over HTTPS
  behind a reverse proxy, not a replacement for one if you're exposing this
  to the open internet.

The container also has read/write access to your Home Assistant configuration
directory, same as the add-on — see the main [README's Safety &
Validation section](../README.md#️-safety--validation) for the write pipeline
(validation, backup/restore, deprecation scanning, etc.), which is unchanged.

## What's different from the Supervisor add-on

Everything that is genuinely a Supervisor/HAOS concept has no standalone
equivalent and is disabled rather than faked:

- **Backups, add-on/app store management, host/OS/network diagnostics,
  Supervisor jobs/metrics, and `opencode serve`-triggered component updates.**
  The matching MCP tools return a clear "requires Home Assistant Supervisor"
  message instead of failing obscurely.
- **The inbound MCP-over-Ingress bridge** (`ha_mcp_server_enabled` in the
  add-on) — it depends on Home Assistant Core's Ingress session headers,
  which don't exist without Supervisor. Not present in this build.
- **ESPHome's web UI reached through Home Assistant Ingress** — minting that
  session requires Supervisor. ESPHome device/YAML management tools that talk
  to Home Assistant Core directly should still work with `HA_ACCESS_TOKEN`
  set, but this path is untested standalone; please file an issue with
  specifics if you rely on it.
- **Automatic Zigbee2MQTT/ESPHome discovery** — the add-on finds these by
  asking Supervisor which add-ons are installed. Standalone, set `Z2M_URL`
  yourself; there's no equivalent for ESPHome discovery.
- **`hab` and `zigporter` CLIs** now point at `HA_URL`/`HA_ACCESS_TOKEN`
  directly instead of the Supervisor proxy. This should work but has seen
  less testing than the Supervisor path — let us know if something's off.

Everything else — config editing/validation with backup/restore, entity and
service tools, LSP YAML completion, screenshots, decision notes, home
briefing, the native HA MCP bridge, startup hooks, PPQ private mode — works
the same way, authenticated with `HA_ACCESS_TOKEN` against `HA_URL` instead of
through Supervisor.

**Less tested than terminal mode:** `INTERFACE_MODE=openchamber`, the
`opencode attach` LAN server, and the PPQ private-mode proxy all carry over
from the add-on with only mechanical changes (dropping Ingress path-rewriting,
swapping the token source) but have not been exercised as thoroughly
standalone as the default terminal path. Please report issues.

## Environment variables

See [`.env.example`](.env.example) for the full, commented list — it mirrors
the add-on's Configuration tab options section by section. A few standalone-only
ones: `HA_URL`, `HA_ACCESS_TOKEN`, `HA_VERIFY_SSL`, `FRONTDOOR_PORT`,
`WEB_USERNAME`/`WEB_PASSWORD`, `HA_CONFIG_DIR`, `BUILD_ARCH`.

`SERIAL_DEVICES` and any bind mount beyond the config directory (`/addons`,
`/addon_configs`) also need the matching `devices:`/`volumes:` entry in
`docker-compose.yml` — setting the environment variable alone does not map
anything into the container.

## Troubleshooting

- **"HA_URL and/or HA_ACCESS_TOKEN are not set" in the logs**: `docker compose
  logs opencode`, then fix `.env` and `docker compose up -d`.
- **Illegal instruction (core dumped)**: your CPU is older than Intel Nehalem
  (2008) / AMD Bulldozer (2011) / Jaguar (2013) and lacks SSE4.2 — see the
  main [README's CPU requirements](../README.md#-getting-started). Nothing
  `CPU_MODE` can do fixes this.
- **MCP tools error with "requires Home Assistant Supervisor"**: expected —
  see "What's different" above.
- Everything else: check `docker compose logs opencode` first; the boot
  sequence logs each configuration decision it makes.
