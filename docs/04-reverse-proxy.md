# Reverse proxy — Ce qui change dans ta config Apache/Nginx

## Ce que le script crée

Il crée **un seul nouveau fichier de config** dédié au MCP.  
Il ne touche à **aucun de tes vhosts existants**.

---

## Apache — ce qui est créé

Fichier : `/etc/apache2/sites-available/mcp-shell.conf`

```apache
<VirtualHost *:443>
    ServerName ton-domaine.fr

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/ton-domaine.fr/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/ton-domaine.fr/privkey.pem

    <Location /mcp/shell>
        ProxyPass http://127.0.0.1:8001/
        ProxyPassReverse http://127.0.0.1:8001/
        ProxyPreserveHost On
        RequestHeader set X-Forwarded-Proto "https"
    </Location>

</VirtualHost>

<VirtualHost *:80>
    ServerName ton-domaine.fr
    Redirect permanent / https://ton-domaine.fr/
</VirtualHost>
```

### Ce que ça fait concrètement

- Toute requête vers `https://ton-domaine.fr/mcp/shell` est transmise à `http://127.0.0.1:8001/`
- Le container MCP répond, Apache retransmet la réponse à Cursor
- Les autres URLs (`/`, `/api`, etc.) ne sont **pas affectées** par ce vhost

### Les modules Apache activés

```bash
a2enmod proxy        # permet ProxyPass
a2enmod proxy_http   # permet le proxy HTTP
a2enmod headers      # permet RequestHeader
a2enmod ssl          # SSL (probablement déjà actif)
```

Ces modules sont standards sur Apache — ils sont probablement déjà activés sur ton VPS.

---

## Nginx — ce qui est créé

Fichier : `/etc/nginx/sites-available/mcp-shell`  
Lien symbolique : `/etc/nginx/sites-enabled/mcp-shell`

```nginx
server {
    listen 443 ssl;
    server_name ton-domaine.fr;

    ssl_certificate /etc/letsencrypt/live/ton-domaine.fr/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/ton-domaine.fr/privkey.pem;

    location /mcp/shell {
        proxy_pass http://127.0.0.1:8001/;
        proxy_http_version 1.1;
        proxy_buffering off;        # important pour le streaming MCP
        proxy_read_timeout 300s;    # timeout long pour les commandes lentes
    }
}
```

---

## Pourquoi `proxy_buffering off` pour Nginx

Le protocole MCP HTTP Streamable envoie les données au fur et à mesure (streaming).  
Si Nginx bufferise les réponses, Cursor ne reçoit rien tant que la commande n'est pas terminée.  
Avec `proxy_buffering off`, chaque chunk est transmis immédiatement.

---

## Impact sur tes projets existants

**Aucun.** Voici pourquoi :

Tes projets (zerok, vitalinfo, codeurbase) ont leurs propres vhosts sur leur propre `ServerName`.  
Le vhost MCP a son propre `ServerName` (ou utilise un `Location` sur un domaine séparé).  
Apache/Nginx route les requêtes par `ServerName` — il n'y a pas de collision.

Exemple de coexistence sur le même VPS :
```
https://zerok.codeurbase.fr      → vhost zerok (existant, non touché)
https://vitalinfo.codeurbase.fr  → vhost vitalinfo (existant, non touché)
https://mcp.codeurbase.fr/mcp/shell → vhost MCP (nouveau)
```

---

## Vérifier que tout est OK après l'install

Pour Apache :
```bash
apache2ctl configtest    # doit afficher "Syntax OK"
systemctl status apache2
```

Pour Nginx :
```bash
nginx -t                 # doit afficher "test is successful"
systemctl status nginx
```

Pour tester le MCP depuis le VPS lui-même :
```bash
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer TON_TOKEN" \
  https://ton-domaine.fr/mcp/shell
# Doit retourner 200 ou 405 (pas 403 ni 502)
```
