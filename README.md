# myVpsAgent-terminal

> Self-hosted MCP shell server for VPS — control your server from Cursor AI via HTTPS.

Give your Cursor AI agent full shell access to your VPS. Run any command, manage Docker containers, read logs — all from a natural language chat in Cursor.

## How it works

```
Cursor AI (local)
      ↕ HTTPS + Bearer token
Apache / Nginx (your VPS)
      ↕ HTTP (localhost only)
MCP Shell container (127.0.0.1:PORT)
      ↕
bash
```

Your MCP container is never exposed directly to the internet — only your existing reverse proxy is.

## Prerequisites

- Ubuntu / Debian VPS
- Docker + Docker Compose
- Apache **or** Nginx already installed
- `openssl` installed (`sudo apt install openssl`)

## Installation

```bash
git clone https://github.com/bannik62/myVpsAgent-terminal.git
cd myVpsAgent-terminal
sudo ./install.sh
```

The script will guide you through:

1. **Reverse proxy detection** — auto-detects Apache or Nginx
2. **Domain / SSL** — 3 options:
   - Existing domain + Let's Encrypt already configured
   - Existing domain + auto certbot
   - IP only + self-signed certificate
3. **Port selection** — shows occupied ports, suggests a free one
4. **Token generation** — auto-generates a secure 32-byte token
5. **Config output** — prints the `mcp.json` snippet ready to paste in Cursor

At the end of the install, you'll get something like:

```json
{
  "mcpServers": {
    "vps-shell": {
      "url": "https://yourdomain.fr/mcp/shell",
      "transport": "http",
      "headers": {
        "Authorization": "Bearer <your-token>"
      }
    }
  }
}
```

Paste this into `~/.cursor/mcp.json` and restart Cursor.

## Usage

Once connected, ask Cursor anything:

```
"Show me running Docker containers"
"Tail the last 50 lines of the nginx error log"
"How much disk space is left?"
"Restart the zerok-backend container"
"Show me the apache config for codeurbase.fr"
```

## Security

- The MCP container listens on `127.0.0.1` only — never exposed to the internet
- All requests require a `Bearer` token in the `Authorization` header
- Apache/Nginx returns `403` for any request without the correct token
- **Keep your token secret** — it gives shell access to your server

### Renew the token

```bash
# Generate a new token
NEW_TOKEN=$(openssl rand -hex 32)

# Update .env
sed -i "s/^MCP_TOKEN=.*/MCP_TOKEN=${NEW_TOKEN}/" .env

# Regenerate reverse proxy config and reload
sudo ./install.sh --reload

# Update your ~/.cursor/mcp.json with the new token
```

## Uninstall

```bash
sudo ./uninstall.sh
```

This will:
- Stop and remove the Docker container
- Remove the reverse proxy config
- Optionally remove the self-signed certificate
- Remove the `.env` file

## Project structure

```
myVpsAgent-terminal/
├── server.js                           ← MCP server (Node.js, HTTP streamable)
├── Dockerfile                          ← node:22-alpine image
├── docker-compose.yml                  ← container config (reads .env)
├── package.json
├── install.sh                          ← interactive installer
├── uninstall.sh                        ← clean uninstaller
├── .env.example                        ← environment variables template
└── templates/
    ├── apache.conf.template            ← Apache + Let's Encrypt
    ├── apache-selfsigned.conf.template ← Apache + self-signed
    ├── nginx.conf.template             ← Nginx + Let's Encrypt
    └── nginx-selfsigned.conf.template  ← Nginx + self-signed
```

## License

MIT
