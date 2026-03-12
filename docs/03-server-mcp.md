# server.js — Comment le MCP reçoit et exécute une commande

## Le flux complet

```
Cursor tape : "montre-moi les logs nginx"
      ↓
Cursor génère une requête HTTP POST vers https://monvps.fr/mcp/shell
  Header: Authorization: Bearer <token>
  Body:   { "method": "tools/call", "params": { "name": "execute_command", "arguments": { "command": "tail -100 /var/log/nginx/error.log" } } }
      ↓
Apache reçoit la requête sur le port 443
  → vérifie SSL
  → transmet à http://127.0.0.1:MCP_PORT/
      ↓
server.js reçoit la requête
  1. Vérifie le token → 403 si mauvais
  2. Vérifie la whitelist → erreur si commande non autorisée
  3. Exécute : bash -c "tail -100 /var/log/nginx/error.log"
  4. Retourne stdout/stderr à Cursor
      ↓
Cursor affiche le résultat dans le chat
```

---

## L'authentification

```js
const auth = req.headers['authorization'];
if (!auth || auth !== `Bearer ${MCP_TOKEN}`) {
  res.writeHead(403);
  res.end(JSON.stringify({ error: 'Forbidden' }));
  return;
}
```

Chaque requête HTTP doit avoir le header `Authorization: Bearer TOKEN`.  
Si le token est absent ou incorrect → **403 immédiat**, la commande n'est jamais exécutée.

---

## La whitelist

```js
if (existsSync(WHITELIST_FILE)) {
  // Charge les lignes de allowed-commands.txt
  allowedPrefixes = lines;
}

function isAllowed(command) {
  if (!allowedPrefixes) return true; // pas de fichier = tout autorisé
  return allowedPrefixes.some(prefix =>
    cmd === prefix || cmd.startsWith(prefix + ' ')
  );
}
```

**Comment ça fonctionne :**  
Si `allowed-commands.txt` contient `tail`, alors :
- `tail -100 /var/log/nginx/error.log` → ✓ autorisé
- `tailscale status` → ✗ bloqué (ne commence pas par `tail ` avec un espace)
- `rm -rf /` → ✗ bloqué

Si le fichier est vide ou absent → toutes les commandes sont autorisées.

---

## L'exécution

```js
const { stdout, stderr } = await execAsync(command, {
  timeout: MCP_TIMEOUT,     // défaut 30s
  maxBuffer: 1024 * 1024 * 5, // max 5MB de sortie
  shell: '/bin/bash',
});
```

La commande est exécutée dans un sous-shell bash.  
- Si elle réussit → stdout retourné à Cursor
- Si elle échoue → stderr + code d'erreur retourné à Cursor
- Si elle dépasse le timeout → erreur de timeout

---

## Le protocole MCP

Le serveur parle le protocole **MCP (Model Context Protocol)** via **HTTP Streamable** — c'est le standard d'Anthropic pour connecter des outils à des LLMs.

Cursor sait nativement parler ce protocole. Il découvre automatiquement les outils disponibles (ici : `execute_command`) au démarrage de chaque conversation.

---

## L'outil exposé

Un seul outil : `execute_command`

| Paramètre | Type | Description |
|---|---|---|
| `command` | string | La commande bash à exécuter |

Retourne le stdout ou stderr de la commande.
