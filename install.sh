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
echo -e "${BOLD}${CYAN}║  homium-audit — Instalador               ║${RESET}"
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

# ─── Verificar dependencias requeridas ───────────────────────────────────────
step "Verificando dependencias"
MISSING_REQ=()

for t in curl openssl bash perl; do
  if command -v "$t" &>/dev/null; then
    ok "$t"
  else
    MISSING_REQ+=("$t")
    err "$t (requerido)"
  fi
done

if [[ ${#MISSING_REQ[@]} -gt 0 ]]; then
  echo ""
  err "Faltan dependencias requeridas: ${MISSING_REQ[*]}"
  case "$OS_TYPE" in
    macos)
      echo -e "  Instala con: ${CYAN}brew install ${MISSING_REQ[*]}${RESET}"
      ;;
    windows)
      echo -e "  Instala ${CYAN}Git for Windows${RESET}: https://git-scm.com/download/win"
      ;;
    linux)
      echo -e "  Instala con: ${CYAN}sudo apt install ${MISSING_REQ[*]}${RESET}"
      ;;
  esac
  exit 1
fi

# ─── Verificar herramientas opcionales ───────────────────────────────────────
step "Herramientas opcionales"

for t in dig whois jq; do
  if command -v "$t" &>/dev/null; then
    ok "$t"
  else
    case "$t" in
      dig)
        case "$OS_TYPE" in
          macos)   warn "dig — brew install bind" ;;
          windows) warn "dig — no disponible en Git Bash (se usará DNS API)" ;;
          linux)   warn "dig — sudo apt install dnsutils" ;;
        esac ;;
      whois)
        case "$OS_TYPE" in
          macos)   warn "whois — brew install whois" ;;
          windows) warn "whois — no disponible en Git Bash (se usará RDAP API)" ;;
          linux)   warn "whois — sudo apt install whois" ;;
        esac ;;
      jq)
        case "$OS_TYPE" in
          macos)   warn "jq — brew install jq" ;;
          windows) warn "jq — https://jqlang.github.io/jq/download/" ;;
          linux)   warn "jq — sudo apt install jq" ;;
        esac ;;
    esac
  fi
done

# Node/npm para herramientas de análisis
NPM_TOOLS_AVAILABLE=false
if command -v node &>/dev/null && command -v npm &>/dev/null; then
  ok "node $(node --version) + npm $(npm --version)"
  NPM_TOOLS_AVAILABLE=true
else
  warn "node/npm no encontrado — Lighthouse, screenshots y análisis WCAG no disponibles"
  case "$OS_TYPE" in
    macos)   echo -e "    Instala: ${CYAN}brew install node${RESET} o https://nodejs.org" ;;
    windows) echo -e "    Instala: ${CYAN}https://nodejs.org${RESET}" ;;
    linux)   echo -e "    Instala: ${CYAN}sudo apt install nodejs npm${RESET}" ;;
  esac
fi

# ─── Instalar herramientas npm ────────────────────────────────────────────────
if [[ "$NPM_TOOLS_AVAILABLE" == true ]]; then
  step "Instalando herramientas de análisis (npm)"

  NPM_GLOBAL_PREFIX=$(npm prefix -g 2>/dev/null || echo "")
  NPM_GLOBAL_BIN="${NPM_GLOBAL_PREFIX}/bin"

  _install_npm() {
    local pkg="$1" cmd="${2:-$1}"
    if command -v "$cmd" &>/dev/null || [[ -f "${NPM_GLOBAL_BIN}/${cmd}" ]]; then
      ok "${pkg} (ya instalado)"
    else
      info "Instalando ${pkg}..."
      if npm install -g "$pkg" --quiet 2>/dev/null; then
        ok "${pkg}"
      else
        warn "${pkg} — no se pudo instalar (puedes instalarlo manualmente: npm i -g ${pkg})"
      fi
    fi
  }

  _install_npm "lighthouse"          "lighthouse"
  _install_npm "@axe-core/cli"       "axe"
  _install_npm "pa11y"               "pa11y"
  _install_npm "htmlhint"            "htmlhint"
fi

# webanalyze — detección de stack tecnológico (Wappalyzer fingerprints)
if command -v webanalyze &>/dev/null; then
  ok "webanalyze (stack tecnológico extendido disponible)"
else
  case "$OS_TYPE" in
    macos)   warn "webanalyze — go install github.com/rverton/webanalyze/cmd/webanalyze@latest  (o: brew install go)" ;;
    linux)   warn "webanalyze — go install github.com/rverton/webanalyze/cmd/webanalyze@latest" ;;
    windows) warn "webanalyze — no disponible en Git Bash (se usará fingerprinting básico)" ;;
  esac
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
        if [[ -f "$rc" ]] && ! grep -q ".local/bin" "$rc"; then
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
echo -e "${BOLD}${GREEN}║  ✓ homium-audit instalado correctamente           ║${RESET}"
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
