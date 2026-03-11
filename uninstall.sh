#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo -e "${BOLD}${RED}╔════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${RED}║   myVpsAgent-terminal  uninstaller     ║${NC}"
echo -e "${BOLD}${RED}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Cette opération va :${NC}"
echo "  - Arrêter et supprimer le container MCP"
echo "  - Supprimer la config du reverse proxy"
echo "  - Supprimer le certificat auto-signé (si applicable)"
echo "  - Supprimer le fichier .env"
echo ""
echo -e "${BOLD}Confirmer la désinstallation ? (o/N)${NC}"
read -r CONFIRM

if [[ ! "$CONFIRM" =~ ^[Oo]$ ]]; then
  echo "Annulé."
  exit 0
fi

# ─── Arrêt du container ──────────────────────

echo ""
echo -e "${BOLD}[1/4] Arrêt du container...${NC}"
cd "$SCRIPT_DIR"
if docker compose ps --quiet 2>/dev/null | grep -q .; then
  docker compose down --rmi local
  echo -e "${GREEN}✓ Container arrêté et supprimé${NC}"
else
  echo -e "${YELLOW}⚠ Aucun container en cours d'exécution${NC}"
fi

# ─── Suppression config reverse proxy ────────

echo ""
echo -e "${BOLD}[2/4] Suppression de la config reverse proxy...${NC}"

APACHE_CONF="/etc/apache2/sites-available/mcp-shell.conf"
NGINX_CONF="/etc/nginx/sites-available/mcp-shell"
NGINX_LINK="/etc/nginx/sites-enabled/mcp-shell"

if [ -f "$APACHE_CONF" ]; then
  a2dissite mcp-shell &>/dev/null || true
  rm -f "$APACHE_CONF"
  systemctl reload apache2 &>/dev/null || true
  echo -e "${GREEN}✓ Config Apache supprimée${NC}"
fi

if [ -f "$NGINX_CONF" ]; then
  rm -f "$NGINX_CONF" "$NGINX_LINK"
  nginx -t &>/dev/null && systemctl reload nginx &>/dev/null || true
  echo -e "${GREEN}✓ Config Nginx supprimée${NC}"
fi

# ─── Suppression certificat auto-signé ───────

echo ""
echo -e "${BOLD}[3/4] Certificat auto-signé...${NC}"

SSL_DIR="/etc/ssl/mcp"
if [ -d "$SSL_DIR" ]; then
  echo -e "Supprimer le certificat auto-signé dans ${SSL_DIR} ? (o/N)"
  read -r DEL_CERT
  if [[ "$DEL_CERT" =~ ^[Oo]$ ]]; then
    rm -rf "$SSL_DIR"
    echo -e "${GREEN}✓ Certificat supprimé${NC}"
  else
    echo -e "${YELLOW}⚠ Certificat conservé${NC}"
  fi
else
  echo -e "${YELLOW}⚠ Aucun certificat auto-signé trouvé${NC}"
fi

# ─── Suppression .env ────────────────────────

echo ""
echo -e "${BOLD}[4/4] Suppression du .env...${NC}"
if [ -f "${SCRIPT_DIR}/.env" ]; then
  rm -f "${SCRIPT_DIR}/.env"
  echo -e "${GREEN}✓ .env supprimé${NC}"
else
  echo -e "${YELLOW}⚠ Aucun .env trouvé${NC}"
fi

# ─── Résumé ──────────────────────────────────

echo ""
echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║  ✓ Désinstallation terminée                    ║${NC}"
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}N'oubliez pas de retirer l'entrée 'vps-shell' de votre ~/.cursor/mcp.json${NC}"
echo ""
