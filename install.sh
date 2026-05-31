#!/usr/bin/env bash
# =============================================================================
# homium-audit — Instalador
# Repo: homium-tech/audit
# Uso: curl -sSL https://raw.githubusercontent.com/homium-tech/audit/main/install.sh | bash
# =============================================================================

set -euo pipefail

REPO="homium-tech/audit"
INSTALL_DIR="${HOME}/.homium-audit"
BIN_DIR="${HOME}/.local/bin"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

# ─── Colors ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

ok()   { echo -e "${GREEN}✓${RESET} $*"; }
info() { echo -e "${CYAN}→${RESET} $*"; }
warn() { echo -e "${YELLOW}⚠${RESET} $*"; }
err()  { echo -e "${RED}✗${RESET} $*" >&2; }
step() { echo -e "\n${BOLD}${CYAN}── $* ──────────────────────────────${RESET}"; }

# ─── Header ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║  homium-audit — Instalador               ║${RESET}"
echo -e "${BOLD}${CYAN}║  github.com/${REPO}    ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${RESET}"
echo ""

# ─── OS Detection ────────────────────────────────────────────────────────────
OS="unknown"
[[ "$OSTYPE" == "linux-gnu"* ]] && OS="linux"
[[ "$OSTYPE" == "darwin"*    ]] && OS="macos"
info "Sistema operativo: ${BOLD}${OS}${RESET}"

# ─── Check required tools ─────────────────────────────────────────────────────
step "Verificando dependencias requeridas"
MISSING_REQ=()
for tool in curl openssl bash; do
  if command -v "$tool" &>/dev/null; then
    ok "$tool"
  else
    MISSING_REQ+=("$tool")
    err "$tool — REQUERIDO"
  fi
done

if [[ ${#MISSING_REQ[@]} -gt 0 ]]; then
  err "Faltan dependencias requeridas: ${MISSING_REQ[*]}"
  err "Instálalas antes de continuar."
  exit 1
fi

# ─── Check optional tools ─────────────────────────────────────────────────────
step "Verificando herramientas opcionales"
for tool in lighthouse htmlq jq node dig; do
  if command -v "$tool" &>/dev/null; then
    ok "$tool (disponible)"
  else
    warn "$tool (no encontrado — análisis parcial en algunas dimensiones)"
  fi
done

echo ""
info "Para instalar Lighthouse (mejora análisis de performance, SEO y accesibilidad):"
echo "    npm install -g lighthouse"
echo ""

# ─── Install ──────────────────────────────────────────────────────────────────
step "Instalando homium-audit"

# Create directories
mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "${HOME}/audits"
ok "Directorios creados"

# Download main script
info "Descargando homium-audit.sh..."
if curl -sSL "${BASE_URL}/homium-audit.sh" -o "${INSTALL_DIR}/homium-audit.sh"; then
  chmod +x "${INSTALL_DIR}/homium-audit.sh"
  ok "Script principal instalado en ${INSTALL_DIR}/homium-audit.sh"
else
  # Fallback: try to copy from current directory
  if [[ -f "$(pwd)/homium-audit.sh" ]]; then
    cp "$(pwd)/homium-audit.sh" "${INSTALL_DIR}/homium-audit.sh"
    chmod +x "${INSTALL_DIR}/homium-audit.sh"
    ok "Script copiado desde directorio actual"
  else
    err "No se pudo descargar homium-audit.sh"
    err "Verifica tu conexión a internet o ejecuta desde el directorio del repositorio."
    exit 1
  fi
fi

# Download Claude Code command
COMMANDS_DIR="${INSTALL_DIR}/commands"
mkdir -p "$COMMANDS_DIR"
info "Descargando comando Claude Code..."
if curl -sSL "${BASE_URL}/commands/homium-audit.md" \
  -o "${COMMANDS_DIR}/homium-audit.md" 2>/dev/null; then
  ok "Comando Claude Code instalado"
else
  warn "No se pudo descargar el comando Claude Code (no crítico)"
fi

# Create symlink in ~/.local/bin
info "Creando symlink en ${BIN_DIR}/homium-audit..."
ln -sf "${INSTALL_DIR}/homium-audit.sh" "${BIN_DIR}/homium-audit"
ok "Symlink creado: ${BIN_DIR}/homium-audit"

# ─── PATH setup ───────────────────────────────────────────────────────────────
step "Configurando PATH"

add_to_path() {
  local file="$1"
  local export_line='export PATH="$HOME/.local/bin:$PATH"'
  if [[ -f "$file" ]] && ! grep -q ".local/bin" "$file"; then
    echo "" >> "$file"
    echo "# homium-audit" >> "$file"
    echo "$export_line" >> "$file"
    ok "PATH añadido a $file"
  fi
}

if ! echo "$PATH" | grep -q ".local/bin"; then
  add_to_path "${HOME}/.bashrc"
  add_to_path "${HOME}/.zshrc"
  add_to_path "${HOME}/.profile"
  warn "PATH actualizado. Reinicia tu terminal o ejecuta: source ~/.bashrc"
else
  ok "PATH ya contiene ~/.local/bin"
fi

# ─── Claude Code integration ──────────────────────────────────────────────────
step "Integrando con Claude Code"

CLAUDE_COMMANDS_DIR="${HOME}/.claude/commands"
if [[ -d "${HOME}/.claude" ]] || [[ -d "${HOME}/.config/claude" ]]; then
  mkdir -p "$CLAUDE_COMMANDS_DIR"
  if [[ -f "${COMMANDS_DIR}/homium-audit.md" ]]; then
    cp "${COMMANDS_DIR}/homium-audit.md" "${CLAUDE_COMMANDS_DIR}/homium-audit.md"
    ok "Comando /homium-audit instalado en Claude Code"
  fi
else
  warn "Claude Code no detectado — el comando /homium-audit se instalará manualmente."
  echo ""
  info "Para instalar el comando en Claude Code manualmente:"
  echo "    mkdir -p ~/.claude/commands"
  echo "    cp ${COMMANDS_DIR}/homium-audit.md ~/.claude/commands/"
fi

# ─── Create audit directory ───────────────────────────────────────────────────
mkdir -p "${HOME}/audits"
ok "Directorio de reportes: ${HOME}/audits/"

# ─── Verify installation ──────────────────────────────────────────────────────
step "Verificando instalación"
if [[ -x "${INSTALL_DIR}/homium-audit.sh" ]]; then
  ok "Instalación completada exitosamente"
else
  err "Algo salió mal durante la instalación"
  exit 1
fi

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔═══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║  ✓ homium-audit instalado correctamente!          ║${RESET}"
echo -e "${BOLD}${GREEN}╚═══════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${BOLD}Uso:${RESET}"
echo -e "    ${CYAN}homium-audit https://ejemplo.com${RESET}"
echo ""
echo -e "  ${BOLD}En Claude Code:${RESET}"
echo -e "    ${CYAN}/homium-audit https://ejemplo.com${RESET}"
echo ""
echo -e "  ${BOLD}Reportes guardados en:${RESET}"
echo -e "    ${CYAN}~/audits/${RESET}"
echo ""
echo -e "  ${BOLD}Más info:${RESET}"
echo -e "    ${CYAN}https://github.com/${REPO}${RESET}"
echo ""

# Reload shell hint
if ! command -v homium-audit &>/dev/null 2>&1; then
  echo -e "  ${YELLOW}⚠ Ejecuta lo siguiente para usar homium-audit sin ruta completa:${RESET}"
  echo -e "    ${CYAN}source ~/.bashrc  # o: source ~/.zshrc${RESET}"
  echo ""
fi
