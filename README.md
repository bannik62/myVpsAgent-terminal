# personal_mcp_codeurbase

MCP servers déployés sur le VPS de production, exposés via Apache reverse proxy.

## Architecture

```
Cursor (local)
    ↕ HTTPS + token
Apache (VPS)
  ├── /mcp/shell     → shell MCP    (127.0.0.1:8001)
  └── /mcp/postgres  → postgres MCP (127.0.0.1:8002)
```

## MCP installés

### shell MCP
Exécution de commandes système sur le VPS depuis Cursor.
- User Linux dédié `mcp-agent` (droits limités, pas root)
- Liste blanche de commandes autorisées
- Port : 8001 (localhost uniquement)

### postgres MCP
Requêtes en langage naturel sur les bases de données.
- User postgres `mcp_readonly` (lecture seule)
- Accès aux BDD : zerok, vitalinfo
- Port : 8002 (localhost uniquement)

## Sécurité

- Les MCP n'écoutent que sur `127.0.0.1` — jamais exposés directement
- Apache gère le HTTPS et l'authentification par token
- Token stocké dans un fichier `.env` (non versionné)

## Installation

```bash
git clone <repo> && cd personal_mcp_codeurbase
cp .env.example .env
# Remplir le token dans .env
./install.sh
```

## Structure

```
personal_mcp_codeurbase/
├── README.md
├── install.sh
├── .env.example
├── shell-mcp/
│   ├── allowed-commands.txt   # commandes autorisées
│   └── shell-mcp.service      # systemd
├── postgres-mcp/
│   └── postgres-mcp.service   # systemd
└── apache/
    ├── mcp-shell.conf          # vhost Apache
    └── mcp-postgres.conf       # vhost Apache
```

## Renouvellement du token

Modifier `MCP_TOKEN` dans `.env` puis :
```bash
./install.sh --reload-apache
```
Mettre à jour le token dans `~/.cursor/mcp.json` côté local.
