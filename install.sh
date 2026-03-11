#!/bin/bash
set -e

# ─────────────────────────────────────────────
#  myVpsAgent-terminal — Install script
# ─────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo -e "${BOLD}${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║     myVpsAgent-terminal  installer     ║${NC}"
echo -e "${BOLD}${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""

# ─── Prérequis ───────────────────────────────

echo -e "${BOLD}[1/6] Vérification des prérequis...${NC}"

if ! command -v docker &>/dev/null; then
  echo -e "${RED}✗ Docker n'est pas installé.${NC}"
  echo "  Installez Docker : https://docs.docker.com/engine/install/"
  exit 1
fi
echo -e "${GREEN}✓ Docker${NC}"

if ! command -v docker compose &>/dev/null && ! docker compose version &>/dev/null 2>&1; then
  echo -e "${RED}✗ Docker Compose n'est pas installé.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Docker Compose${NC}"

if ! command -v openssl &>/dev/null; then
  echo -e "${RED}✗ openssl n'est pas installé.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ openssl${NC}"

# ─── Choix du reverse proxy ──────────────────

echo ""
echo -e "${BOLD}[2/6] Reverse proxy...${NC}"

PROXY=""
if command -v apache2 &>/dev/null || command -v httpd &>/dev/null; then
  echo -e "  ${GREEN}Apache détecté${NC}"
  PROXY="apache"
fi
if command -v nginx &>/dev/null; then
  echo -e "  ${GREEN}Nginx détecté${NC}"
  [ -z "$PROXY" ] && PROXY="nginx"
fi

if [ -z "$PROXY" ]; then
  echo -e "${RED}✗ Aucun reverse proxy détecté (Apache ou Nginx requis).${NC}"
  exit 1
fi

echo -e "Utiliser ${CYAN}${PROXY}${NC} ? (O/n)"
read -r PROXY_CONFIRM
if [[ "$PROXY_CONFIRM" =~ ^[Nn]$ ]]; then
  if [ "$PROXY" = "apache" ] && command -v nginx &>/dev/null; then
    PROXY="nginx"
  else
    PROXY="apache"
  fi
fi
echo -e "${GREEN}✓ Reverse proxy : ${PROXY}${NC}"

# ─── Domaine ou IP ───────────────────────────

echo ""
echo -e "${BOLD}[3/6] Domaine / SSL...${NC}"

echo -e "Avez-vous un domaine pointant vers ce serveur ? (O/n)"
read -r HAS_DOMAIN

SSL_MODE=""
DOMAIN_OR_IP=""

if [[ ! "$HAS_DOMAIN" =~ ^[Nn]$ ]]; then
  echo -n "Votre domaine (ex: monvps.fr) : "
  read -r DOMAIN_OR_IP

  echo -e "SSL Let's Encrypt déjà configuré pour ce domaine ? (O/n)"
  read -r HAS_SSL

  if [[ ! "$HAS_SSL" =~ ^[Nn]$ ]]; then
    SSL_MODE="letsencrypt"
    # Cherche le cert Let's Encrypt existant
    SSL_CERT="/etc/letsencrypt/live/${DOMAIN_OR_IP}/fullchain.pem"
    SSL_KEY="/etc/letsencrypt/live/${DOMAIN_OR_IP}/privkey.pem"
    if [ ! -f "$SSL_CERT" ]; then
      echo -e "${YELLOW}⚠ Certificat Let's Encrypt introuvable pour ${DOMAIN_OR_IP}.${NC}"
      echo -e "  Lancement de certbot..."
      if command -v certbot &>/dev/null; then
        if [ "$PROXY" = "apache" ]; then
          certbot --apache -d "$DOMAIN_OR_IP" --non-interactive --agree-tos -m "admin@${DOMAIN_OR_IP}"
        else
          certbot --nginx -d "$DOMAIN_OR_IP" --non-interactive --agree-tos -m "admin@${DOMAIN_OR_IP}"
        fi
      else
        echo -e "${RED}✗ certbot non installé. Installez-le : sudo apt install certbot${NC}"
        exit 1
      fi
    fi
    echo -e "${GREEN}✓ SSL Let's Encrypt${NC}"
  else
    SSL_MODE="selfsigned"
    echo -e "${YELLOW}⚠ Certificat auto-signé sera généré.${NC}"
  fi
else
  # Pas de domaine — IP + cert auto-signé
  DOMAIN_OR_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
  echo -e "  IP détectée : ${CYAN}${DOMAIN_OR_IP}${NC}"
  SSL_MODE="selfsigned"
  echo -e "${YELLOW}⚠ Certificat auto-signé sera utilisé (Cursor affichera un avertissement SSL).${NC}"
fi

# Génération du certificat auto-signé si besoin
if [ "$SSL_MODE" = "selfsigned" ]; then
  SSL_DIR="/etc/ssl/mcp"
  mkdir -p "$SSL_DIR"
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "${SSL_DIR}/key.pem" \
    -out "${SSL_DIR}/cert.pem" \
    -subj "/CN=${DOMAIN_OR_IP}" &>/dev/null
  SSL_CERT="${SSL_DIR}/cert.pem"
  SSL_KEY="${SSL_DIR}/key.pem"
  echo -e "${GREEN}✓ Certificat auto-signé généré${NC}"
fi

# ─── Port ────────────────────────────────────

echo ""
echo -e "${BOLD}[4/6] Port du serveur MCP...${NC}"
echo -e "Ports déjà utilisés sur ce serveur :"
ss -tlnp 2>/dev/null | grep LISTEN | awk '{print "  " $4}' | sort
echo ""

DEFAULT_PORT=8001
while ss -tlnp 2>/dev/null | grep -q ":${DEFAULT_PORT}"; do
  DEFAULT_PORT=$((DEFAULT_PORT + 1))
done

echo -n "Port à utiliser (défaut: ${DEFAULT_PORT}) : "
read -r MCP_PORT
MCP_PORT="${MCP_PORT:-$DEFAULT_PORT}"

if ss -tlnp 2>/dev/null | grep -q ":${MCP_PORT}"; then
  echo -e "${RED}✗ Le port ${MCP_PORT} est déjà utilisé.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Port : ${MCP_PORT}${NC}"

# ─── Token ───────────────────────────────────

echo ""
echo -e "${BOLD}[5/6] Génération du token de sécurité...${NC}"
MCP_TOKEN=$(openssl rand -hex 32)
echo -e "${GREEN}✓ Token généré${NC}"

# ─── Installation ────────────────────────────

echo ""
echo -e "${BOLD}[6/6] Installation...${NC}"

# Écriture du .env
cat > "${SCRIPT_DIR}/.env" <<EOF
MCP_TOKEN=${MCP_TOKEN}
MCP_PORT=${MCP_PORT}
EOF
echo -e "${GREEN}✓ .env créé${NC}"

# Choix du bon template
if [ "$SSL_MODE" = "selfsigned" ]; then
  TEMPLATE="${SCRIPT_DIR}/templates/${PROXY}-selfsigned.conf.template"
else
  TEMPLATE="${SCRIPT_DIR}/templates/${PROXY}.conf.template"
fi

# Génération de la config reverse proxy
CONF_CONTENT=$(cat "$TEMPLATE")
CONF_CONTENT="${CONF_CONTENT//\{\{DOMAIN\}\}/$DOMAIN_OR_IP}"
CONF_CONTENT="${CONF_CONTENT//\{\{IP\}\}/$DOMAIN_OR_IP}"
CONF_CONTENT="${CONF_CONTENT//\{\{MCP_PORT\}\}/$MCP_PORT}"
CONF_CONTENT="${CONF_CONTENT//\{\{MCP_TOKEN\}\}/$MCP_TOKEN}"
CONF_CONTENT="${CONF_CONTENT//\{\{SSL_CERT\}\}/$SSL_CERT}"
CONF_CONTENT="${CONF_CONTENT//\{\{SSL_KEY\}\}/$SSL_KEY}"

if [ "$PROXY" = "apache" ]; then
  CONF_FILE="/etc/apache2/sites-available/mcp-shell.conf"
  echo "$CONF_CONTENT" > "$CONF_FILE"
  a2enmod proxy proxy_http headers ssl &>/dev/null
  a2ensite mcp-shell &>/dev/null
  systemctl reload apache2
  echo -e "${GREEN}✓ Apache configuré et rechargé${NC}"
else
  CONF_FILE="/etc/nginx/sites-available/mcp-shell"
  echo "$CONF_CONTENT" > "$CONF_FILE"
  ln -sf "$CONF_FILE" /etc/nginx/sites-enabled/mcp-shell
  nginx -t &>/dev/null && systemctl reload nginx
  echo -e "${GREEN}✓ Nginx configuré et rechargé${NC}"
fi

# Lancement du container
cd "$SCRIPT_DIR"
docker compose up -d --build
echo -e "${GREEN}✓ Container MCP démarré${NC}"

# ─── Résumé ──────────────────────────────────

MCP_URL="https://${DOMAIN_OR_IP}/mcp/shell"

echo ""
echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║  ✓ Installation terminée !                     ║${NC}"
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}Copiez cette config dans ~/.cursor/mcp.json :${NC}"
echo ""
echo -e "${CYAN}{${NC}"
echo -e "${CYAN}  \"mcpServers\": {${NC}"
echo -e "${CYAN}    \"vps-shell\": {${NC}"
echo -e "${CYAN}      \"url\": \"${MCP_URL}\",${NC}"
echo -e "${CYAN}      \"transport\": \"http\",${NC}"
echo -e "${CYAN}      \"headers\": {${NC}"
echo -e "${CYAN}        \"Authorization\": \"Bearer ${MCP_TOKEN}\"${NC}"
echo -e "${CYAN}      }${NC}"
echo -e "${CYAN}    }${NC}"
echo -e "${CYAN}  }${NC}"
echo -e "${CYAN}}${NC}"
echo ""
if [ "$SSL_MODE" = "selfsigned" ]; then
  echo -e "${YELLOW}⚠ Certificat auto-signé : Cursor peut afficher un avertissement SSL.${NC}"
fi
echo -e "${YELLOW}⚠ Gardez ce token secret — il donne accès à votre serveur.${NC}"
echo ""
