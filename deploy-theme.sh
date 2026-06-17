#!/bin/bash
# =============================================================================
# deploy-theme.sh — Safe theme-only deployment for AIVA ERP
#
# Run this on the production server after pushing logicsky_theme to GitHub.
# Only touches CSS/JS files — never rebuilds frappe/erpnext bundles.
#
# Usage:
#   ./scripts/deploy-theme.sh
# =============================================================================

set -e

BACKEND_CONTAINER="frappe_docker-backend-1"
APP_DIR="/home/frappe/frappe-bench/apps/logicsky_theme"
ASSETS_DIR="/home/frappe/frappe-bench/sites/assets/logicsky_theme"

echo "==> Pulling latest theme from GitHub..."
# Works from both local (../apps) and server (/opt/frappe/logicsky-dev/apps)
THEME_DIR="$(dirname "$0")/../apps/logicsky_theme"
[ -d "$THEME_DIR" ] || THEME_DIR="/opt/frappe/logicsky-dev/apps/logicsky_theme"
cd "$THEME_DIR"
git pull origin main

echo "==> Copying CSS and JS to sites/assets (no bench build — safe)..."
docker exec "$BACKEND_CONTAINER" bash -c "
  mkdir -p ${ASSETS_DIR}/css ${ASSETS_DIR}/js

  cp ${APP_DIR}/logicsky_theme/public/css/logicsky.css \
     ${ASSETS_DIR}/css/logicsky.css

  cp ${APP_DIR}/logicsky_theme/public/js/logicsky.js \
     ${ASSETS_DIR}/js/logicsky.js

  echo 'Files copied:'
  ls -lh ${ASSETS_DIR}/css/logicsky.css
  ls -lh ${ASSETS_DIR}/js/logicsky.js
"

echo "==> Clearing Frappe cache..."
docker exec "$BACKEND_CONTAINER" bench --site all clear-cache

echo ""
echo "Done. Theme deployed successfully."
echo "Ask users to hard-refresh (Ctrl+Shift+R / Cmd+Shift+R)."
