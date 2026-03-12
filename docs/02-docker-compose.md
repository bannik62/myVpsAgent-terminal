# docker-compose.yml — Ce qui tourne et pourquoi

## Le fichier complet

```yaml
services:
  shell-mcp:
    image: vps-mcp-shell
    build: .
    container_name: mcp-shell
    restart: unless-stopped
    volumes:
      - /home:/home:ro
      - /var/log:/var/log:ro
      - /etc:/etc:ro
      - ./allowed-commands.txt:/app/allowed-commands.txt:ro
    ports:
      - "127.0.0.1:${MCP_PORT}:8000"
    environment:
      - MCP_TOKEN=${MCP_TOKEN}
      - MCP_TIMEOUT=${MCP_TIMEOUT:-30000}
```

---

## Chaque ligne expliquée

### `image: vps-mcp-shell` + `build: .`
Docker utilise l'image locale nommée `vps-mcp-shell`. Si elle n'existe pas, il la construit depuis le `Dockerfile` dans le dossier courant.

### `restart: unless-stopped`
Le container redémarre automatiquement si le VPS reboot ou si le container crash — sauf si tu l'as arrêté manuellement avec `docker compose down`.

### `ports: "127.0.0.1:${MCP_PORT}:8000"`
Le container écoute sur le port `8000` en interne.  
À l'extérieur du container, il est accessible uniquement sur `127.0.0.1:MCP_PORT` — **jamais sur `0.0.0.0`**, donc jamais directement exposé à internet.  
Apache/Nginx font le pont entre internet et ce port local.

---

## Les volumes montés

Tous les volumes sont montés en **lecture seule** (`:ro`) — le container peut lire mais jamais écrire.

### `/home:/home:ro`
Donne accès aux home directories du VPS.  
Utile pour lire les configs de projets, les `.env`, les logs applicatifs.  
**Exemple :** `cat /home/ubuntu/project/zerok-billing/.env`

### `/var/log:/var/log:ro`
Donne accès aux logs système.  
**Exemple :** `tail -f /var/log/apache2/error.log`

### `/etc:/etc:ro`
Donne accès aux configs système.  
**Exemple :** `cat /etc/apache2/sites-enabled/zerok.conf`

### `./allowed-commands.txt:/app/allowed-commands.txt:ro`
Monte la liste blanche des commandes autorisées dans le container.  
Le serveur Node.js lit ce fichier au démarrage.

---

## Les variables d'environnement

### `MCP_TOKEN`
Le token secret. Injecté dans le container, vérifié par `server.js` à chaque requête.

### `MCP_TIMEOUT`
Timeout en millisecondes pour l'exécution des commandes. Défaut : 30 secondes.  
À augmenter si tu veux lancer des commandes longues (`apt upgrade`, compilation...).

---

## Ce que le container peut ET ne peut PAS faire

| Action | Possible | Pourquoi |
|---|---|---|
| Lire `/home/ubuntu/project/...` | ✓ | Volume monté en lecture |
| Lire `/var/log/syslog` | ✓ | Volume monté en lecture |
| Lire `/etc/apache2/...` | ✓ | Volume monté en lecture |
| Écrire un fichier | ✗ | Tous les volumes sont `:ro` |
| Accéder à Docker | ✗ | Socket non monté |
| Accéder à la base de données | ✗ | Pas de volume DB monté |
| Écouter sur internet directement | ✗ | Port lié à `127.0.0.1` uniquement |
