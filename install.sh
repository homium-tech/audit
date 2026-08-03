#!/usr/bin/env bash
# =============================================================================
# homium-audit — Instalador
# Repo: homium-tech/audit
# Uso: curl -sSL https://raw.githubusercontent.com/homium-tech/audit/main/install.sh | bash
# =============================================================================

# ─── Detectar entorno ────────────────────────────────────────────────────────
OS_TYPE="linux"
[[ "$OSTYPE" == "darwin"* ]] && OS_TYPE="macos"
[[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]] && OS_TYPE="windows"

REPO="homium-tech/audit"
VERSION="1.11.0"
INSTALL_DIR="${HOME}/.homium-audit"
BIN_DIR="${HOME}/.local/bin"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

# ─── Colors ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'

ok()   { echo -e "${GREEN}✓${RESET} $*"; }
info() { echo -e "${CYAN}→${RESET} $*"; }
warn() { echo -e "${YELLOW}⚠${RESET} $*"; }
err()  { echo -e "${RED}✗${RESET} $*" >&2; }
step() { echo -e "\n${BOLD}${CYAN}── $* ──────────────────────────────${RESET}"; }

# ─── Header ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║  homium-audit v${VERSION} — Instalador       ║${RESET}"
echo -e "${BOLD}${CYAN}║  github.com/${REPO}      ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${RESET}"
echo ""

# ─── Info de entorno ─────────────────────────────────────────────────────────
case "$OS_TYPE" in
  macos)
    info "Sistema: macOS"
    info "Shell: ${SHELL:-bash}"
    ;;
  windows)
    info "Sistema: Windows (Git Bash / MSYS2)"
    echo ""
    echo -e "  ${YELLOW}Requisitos en Windows:${RESET}"
    echo -e "  • Git for Windows (incluye bash, curl, perl, openssl)"
    echo -e "    https://git-scm.com/download/win"
    echo -e "  • Node.js para herramientas opcionales (lighthouse, etc.)"
    echo -e "    https://nodejs.org"
    echo ""
    ;;
  linux)
    info "Sistema: Linux"
    ;;
esac

# ─── Helpers de instalación automática ───────────────────────────────────────

# Detectar gestor de paquetes Linux
LINUX_PKG=""
if [[ "$OS_TYPE" == "linux" ]]; then
  command -v apt-get &>/dev/null && LINUX_PKG="apt"
  command -v dnf     &>/dev/null && LINUX_PKG="dnf"
  command -v yum     &>/dev/null && LINUX_PKG="yum"
  command -v pacman  &>/dev/null && LINUX_PKG="pacman"
fi

# Instalar paquete según plataforma
_install_pkg() {
  local name="$1" brew_pkg="${2:-$1}" apt_pkg="${3:-$1}" dnf_pkg="${4:-$1}"
  info "Instalando ${name}..."
  case "$OS_TYPE" in
    macos)
      brew install "$brew_pkg" --quiet 2>/dev/null && ok "$name" && return 0 ;;
    linux)
      case "$LINUX_PKG" in
        apt)    sudo apt-get install -y "$apt_pkg" -qq 2>/dev/null && ok "$name" && return 0 ;;
        dnf|yum) sudo "$LINUX_PKG" install -y "$dnf_pkg" 2>/dev/null && ok "$name" && return 0 ;;
        pacman) sudo pacman -S --noconfirm "$apt_pkg" 2>/dev/null  && ok "$name" && return 0 ;;
      esac ;;
  esac
  warn "$name — no se pudo instalar automáticamente"
  return 1
}

# ─── Homebrew (macOS) ─────────────────────────────────────────────────────────
if [[ "$OS_TYPE" == "macos" ]] && ! command -v brew &>/dev/null; then
  step "Instalando Homebrew"
  info "Homebrew es necesario para instalar las dependencias en macOS..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Añadir brew al PATH de la sesión actual
  [[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
  [[ -f /usr/local/bin/brew    ]] && eval "$(/usr/local/bin/brew shellenv)"
  command -v brew &>/dev/null && ok "Homebrew instalado" || { err "No se pudo instalar Homebrew"; exit 1; }
fi

# ─── Dependencias requeridas ──────────────────────────────────────────────────
step "Verificando dependencias"

for t in curl openssl perl; do
  if command -v "$t" &>/dev/null; then
    ok "$t"
  else
    _install_pkg "$t" || { err "$t es requerido y no se pudo instalar"; exit 1; }
  fi
done

# ─── Herramientas opcionales ──────────────────────────────────────────────────
step "Instalando herramientas"

# jq
if command -v jq &>/dev/null; then
  ok "jq"
else
  _install_pkg "jq" "jq" "jq" "jq" || warn "jq no disponible — algunas métricas de Lighthouse no estarán disponibles"
fi

# dig
if command -v dig &>/dev/null; then
  ok "dig"
elif [[ "$OS_TYPE" == "windows" ]]; then
  info "dig → se usará DNS API como fallback"
else
  _install_pkg "dig" "bind" "dnsutils" "bind-utils" || info "dig no disponible — se usará DNS API"
fi

# whois
if command -v whois &>/dev/null; then
  ok "whois"
elif [[ "$OS_TYPE" == "windows" ]]; then
  info "whois → se usará RDAP API como fallback"
else
  _install_pkg "whois" "whois" "whois" "whois" || info "whois no disponible — se usará RDAP API"
fi

# Node.js
if command -v node &>/dev/null && command -v npm &>/dev/null; then
  ok "node $(node --version) + npm $(npm --version)"
elif [[ "$OS_TYPE" == "windows" ]]; then
  warn "node/npm no encontrado — instala Node.js desde https://nodejs.org"
else
  _install_pkg "node" "node" "nodejs npm" "nodejs npm" || warn "node/npm no disponible — Lighthouse no estará disponible"
fi

# npx (confirmación)
if command -v npx &>/dev/null; then
  ok "npx — lighthouse, axe-core, pa11y y htmlhint se ejecutarán bajo demanda"
fi

# Chrome / Chromium (requerido por Lighthouse)
_chrome_found=false
command -v google-chrome        &>/dev/null && _chrome_found=true
command -v google-chrome-stable &>/dev/null && _chrome_found=true
command -v chromium             &>/dev/null && _chrome_found=true
command -v chromium-browser     &>/dev/null && _chrome_found=true
[[ -f "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]] && _chrome_found=true

if [[ "$_chrome_found" == true ]]; then
  ok "Chrome/Chromium detectado — Lighthouse podrá ejecutarse"
elif [[ "$OS_TYPE" == "windows" ]]; then
  warn "Chrome no detectado — instala Google Chrome para habilitar Lighthouse"
else
  info "Chrome/Chromium no detectado — instalando Chromium para Lighthouse..."
  _install_pkg "chromium" "chromium" "chromium-browser" "chromium" && _chrome_found=true \
    || warn "Chromium no se pudo instalar — instala Google Chrome manualmente para habilitar Lighthouse"
fi

# Go + webanalyze
if command -v webanalyze &>/dev/null; then
  ok "webanalyze"
elif [[ "$OS_TYPE" == "windows" ]]; then
  if command -v go &>/dev/null; then
    info "Instalando webanalyze..."
    go install github.com/rverton/webanalyze/cmd/webanalyze@latest 2>/dev/null && ok "webanalyze" || warn "webanalyze — no se pudo instalar"
  else
    warn "webanalyze — instala Go desde https://go.dev/dl para habilitar detección de stack tecnológico"
  fi
else
  if ! command -v go &>/dev/null; then
    _install_pkg "go" "go" "golang" "golang" || true
    # Añadir GOPATH al PATH de la sesión actual
    export PATH="$PATH:$(go env GOPATH 2>/dev/null)/bin"
  fi
  if command -v go &>/dev/null; then
    info "Instalando webanalyze..."
    go install github.com/rverton/webanalyze/cmd/webanalyze@latest 2>/dev/null \
      && ok "webanalyze" || warn "webanalyze — no se pudo instalar"
  fi
fi

# ─── Instalar ─────────────────────────────────────────────────────────────────
step "Instalando homium-audit"

mkdir -p "$INSTALL_DIR"
mkdir -p "${HOME}/audits"
ok "Directorios creados"

# Descargar script principal
info "Descargando homium-audit.sh..."
if curl -sSL "${BASE_URL}/homium-audit.sh" -o "${INSTALL_DIR}/homium-audit.sh" 2>/dev/null; then
  chmod +x "${INSTALL_DIR}/homium-audit.sh"
  ok "Script instalado en ${INSTALL_DIR}/homium-audit.sh"
elif [[ -f "$(pwd)/homium-audit.sh" ]]; then
  cp "$(pwd)/homium-audit.sh" "${INSTALL_DIR}/homium-audit.sh"
  chmod +x "${INSTALL_DIR}/homium-audit.sh"
  ok "Script copiado desde directorio actual"
else
  err "No se pudo obtener homium-audit.sh"
  err "Descarga manualmente desde: https://github.com/${REPO}"
  exit 1
fi

# Descargar comando Claude Code
mkdir -p "${INSTALL_DIR}/commands"
if curl -sSL "${BASE_URL}/commands/homium-audit.md" \
  -o "${INSTALL_DIR}/commands/homium-audit.md" 2>/dev/null; then
  ok "Comando Claude Code descargado"
fi

# ─── Configurar PATH según OS ─────────────────────────────────────────────────
step "Configurando acceso al comando"

case "$OS_TYPE" in
  windows)
    # En Git Bash el PATH más confiable es ~/bin
    BIN_DIR="${HOME}/bin"
    mkdir -p "$BIN_DIR"
    cp "${INSTALL_DIR}/homium-audit.sh" "${BIN_DIR}/homium-audit"
    chmod +x "${BIN_DIR}/homium-audit"
    ok "Copiado en ${BIN_DIR}/homium-audit"

    # Añadir ~/bin al PATH en .bashrc si no está
    if ! grep -q 'HOME/bin' "${HOME}/.bashrc" 2>/dev/null; then
      echo '' >> "${HOME}/.bashrc"
      echo '# homium-audit' >> "${HOME}/.bashrc"
      echo 'export PATH="$HOME/bin:$PATH"' >> "${HOME}/.bashrc"
      ok "PATH actualizado en ~/.bashrc"
    fi
    ;;

  macos|linux)
    mkdir -p "$BIN_DIR"
    ln -sf "${INSTALL_DIR}/homium-audit.sh" "${BIN_DIR}/homium-audit"
    ok "Symlink creado: ${BIN_DIR}/homium-audit"

    # Añadir ~/.local/bin al PATH si no está
    if ! echo "$PATH" | grep -q ".local/bin"; then
      for rc in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile"; do
        # No usar [[ -f "$rc" ]] como filtro: en un Mac recién configurado
        # ~/.zshrc no existe por defecto, y eso hacía que el loop no
        # escribiera en ningún lado, dejando el PATH sin actualizar.
        touch "$rc" 2>/dev/null
        if ! grep -q ".local/bin" "$rc" 2>/dev/null; then
          echo '' >> "$rc"
          echo '# homium-audit' >> "$rc"
          echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
          ok "PATH añadido a $rc"
        fi
      done
    else
      ok "PATH ya contiene ~/.local/bin"
    fi
    ;;
esac

# ─── Integración con Claude Code ─────────────────────────────────────────────
step "Integrando con Claude Code"

CLAUDE_COMMANDS_DIR="${HOME}/.claude/commands"
if [[ -d "${HOME}/.claude" ]] || [[ -d "${HOME}/.config/claude" ]]; then
  mkdir -p "$CLAUDE_COMMANDS_DIR"
  cp "${INSTALL_DIR}/commands/homium-audit.md" "${CLAUDE_COMMANDS_DIR}/homium-audit.md" 2>/dev/null && \
    ok "Comando /homium-audit instalado en Claude Code" || \
    warn "No se pudo instalar el comando Claude Code"
else
  warn "Claude Code no detectado — instala el comando manualmente:"
  echo "    mkdir -p ~/.claude/commands"
  echo "    cp ${INSTALL_DIR}/commands/homium-audit.md ~/.claude/commands/"
fi

# ─── Listo ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔═══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║  ✓ homium-audit v${VERSION} instalado correctamente  ║${RESET}"
echo -e "${BOLD}${GREEN}╚═══════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${BOLD}Uso en terminal:${RESET}"
echo -e "    ${CYAN}homium-audit https://ejemplo.com${RESET}"
echo -e "    ${CYAN}homium-audit https://ejemplo.com --sector ecommerce${RESET}"
echo -e "    ${CYAN}homium-audit https://ejemplo.com --dimensions seo,performance${RESET}"
echo ""
echo -e "  ${BOLD}Uso en Claude Code:${RESET}"
echo -e "    ${CYAN}/homium-audit https://ejemplo.com${RESET}"
echo ""
echo -e "  ${BOLD}Actualizar en el futuro:${RESET}"
echo -e "    ${CYAN}homium-audit --update${RESET}"
echo ""
echo -e "  ${BOLD}Reportes en:${RESET} ${CYAN}~/audits/${RESET}"
echo ""

# Aviso de recarga según OS
case "$OS_TYPE" in
  windows)
    echo -e "  ${YELLOW}Reinicia Git Bash para que el comando esté disponible.${RESET}"
    ;;
  macos|linux)
    if ! command -v homium-audit &>/dev/null 2>&1; then
      echo -e "  ${YELLOW}Ejecuta: source ~/.bashrc  (o abre una nueva terminal)${RESET}"
    fi
    ;;
esac
echo ""
