# install.sh — Ce que fait le script étape par étape

## Vue d'ensemble

`install.sh` doit être lancé avec `sudo` car il écrit dans `/etc/apache2` ou `/etc/nginx` et recharge le service.

```bash
sudo ./install.sh
```

---

## Étape 1 — Vérification des prérequis

```bash
command -v docker
command -v docker compose
command -v openssl
```

Le script vérifie que ces 3 outils sont disponibles. Si l'un manque, il s'arrête avec un message d'erreur. Il n'installe rien automatiquement.

---

## Étape 2 — Détection du reverse proxy

```bash
command -v apache2   # ou httpd
command -v nginx
```

Il cherche Apache ou Nginx sur le système. S'il en trouve un, il propose de l'utiliser. S'il en trouve deux, il prend Apache par défaut et te demande confirmation. S'il n'en trouve aucun, il s'arrête.

**Ce qu'il ne fait pas :** il ne modifie pas tes vhosts existants. Il crée un nouveau fichier de config dédié au MCP.

---

## Étape 3 — Domaine / SSL

Trois cas possibles :

### Cas 1 — Tu as un domaine + Let's Encrypt déjà en place
Le script cherche le certificat dans `/etc/letsencrypt/live/TON_DOMAINE/`.  
S'il le trouve → il l'utilise directement.  
S'il ne le trouve pas → il lance `certbot` automatiquement.

### Cas 2 — Tu as un domaine mais pas encore de SSL
Le script lance :
```bash
certbot --apache -d TON_DOMAINE ...
# ou
certbot --nginx -d TON_DOMAINE ...
```
Certbot doit être installé (`sudo apt install certbot`).

### Cas 3 — Tu n'as pas de domaine (IP uniquement)
Le script génère un certificat auto-signé dans `/etc/ssl/mcp/` :
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/mcp/key.pem \
  -out /etc/ssl/mcp/cert.pem \
  -subj "/CN=TON_IP"
```
Cursor affichera un avertissement SSL — c'est normal avec un cert auto-signé.

---

## Étape 4 — Choix du port

Le script affiche les ports déjà utilisés :
```bash
ss -tlnp | grep LISTEN
```

Il propose automatiquement le premier port libre à partir de `8001`. Tu peux accepter ou choisir un autre.  
Le port choisi sera stocké dans `.env` et utilisé par Docker.

---

## Étape 5 — Génération du token

```bash
openssl rand -hex 32
```

Génère un token aléatoire de 64 caractères hexadécimaux. Ce token est le **seul moyen de s'authentifier** auprès du MCP. Il est stocké dans `.env` et injecté dans le container Docker.

---

## Étape 6 — Installation

### 6a — Écriture du `.env`
```
MCP_TOKEN=<token généré>
MCP_PORT=<port choisi>
MCP_TIMEOUT=30000
```

### 6b — Génération de la config reverse proxy
Le script prend le bon template dans `templates/` et remplace les variables :
- `{{DOMAIN}}` ou `{{IP}}` → ton domaine ou IP
- `{{MCP_PORT}}` → le port choisi
- `{{MCP_TOKEN}}` → le token généré
- `{{SSL_CERT}}` / `{{SSL_KEY}}` → chemins des certificats

Le fichier généré est copié dans :
- Apache : `/etc/apache2/sites-available/mcp-shell.conf`
- Nginx : `/etc/nginx/sites-available/mcp-shell`

### 6c — Activation du vhost
Pour Apache :
```bash
a2enmod proxy proxy_http headers ssl
a2ensite mcp-shell
systemctl reload apache2
```

Pour Nginx :
```bash
ln -sf /etc/nginx/sites-available/mcp-shell /etc/nginx/sites-enabled/mcp-shell
nginx -t
systemctl reload nginx
```

### 6d — Lancement du container
```bash
docker compose up -d --build
```
Construit l'image depuis le `Dockerfile` local et démarre le container en arrière-plan.

---

## Ce que le script NE fait PAS

- Il ne modifie pas tes vhosts existants (zerok, vitalinfo, codeurbase...)
- Il n'installe pas Docker
- Il n'installe pas Apache/Nginx
- Il ne touche pas à ta base de données
- Il ne crée pas d'utilisateur système
